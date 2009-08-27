create or replace function londiste.local_add_table(
    in i_queue_name     text,
    in i_table_name     text,
    out ret_code        int4,
    out ret_note        text)
as $$
-- ----------------------------------------------------------------------
-- Function: londiste.local_add_table(2)
--
--      Register table on Londiste node.
--
-- Returns:
--      200 - Ok
--      301 - Warning, trigger exists that will fire before londiste one
--      400 - No such set
-- ----------------------------------------------------------------------
declare
    col_types text;
    fq_table_name text;
    new_state text;

    logtrg_name text;
    logtrg_previous text;
    logtrg text;
    tbl record;
begin
    fq_table_name := londiste.make_fqname(i_table_name);
    col_types := londiste.find_column_types(fq_table_name);
    if position('k' in col_types) < 1 then
        -- allow missing primary key in case of combined table where
        -- pkey was removed by londiste
        perform 1 from londiste.table_info t,
            pgq_node.node_info n_this,
            pgq_node.node_info n_other
          where n_this.queue_name = i_queue_name
            and n_other.combined_queue = n_this.combined_queue
            and n_other.queue_name <> n_this.queue_name
            and t.queue_name = n_other.queue_name
            and t.table_name = fq_table_name
            and t.dropped_ddl is not null;
        if not found then
            select 400, 'Primary key missing on table: ' || fq_table_name into ret_code, ret_note;
            return;
        end if;
    end if;

    perform 1 from pgq_node.node_info where queue_name = i_queue_name;
    if not found then
        select 400, 'No such set: ' || i_queue_name into ret_code, ret_note;
        return;
    end if;

    select merge_state, local into tbl
        from londiste.table_info
        where queue_name = i_queue_name and table_name = fq_table_name;
    if not found then
        -- add to set on root
        if pgq_node.is_root_node(i_queue_name) then
            select f.ret_code, f.ret_note into ret_code, ret_note
                from londiste.global_add_table(i_queue_name, i_table_name) f;
            if ret_code <> 200 then
                return;
            end if;
        else
            select 404, 'Table not available on queue: ' || fq_table_name
                into ret_code, ret_note;
            return;
        end if;

        -- reload info
        select merge_state, local into tbl
            from londiste.table_info
            where queue_name = i_queue_name and table_name = fq_table_name;
    end if;

    if tbl.local then
        select 200, 'Table already added: ' || fq_table_name into ret_code, ret_note;
        return;
    end if;

    if pgq_node.is_root_node(i_queue_name) then
        new_state := 'ok';
        perform londiste.root_notify_change(i_queue_name, 'londiste.add-table', fq_table_name);
    else
        new_state := NULL;
    end if;

    update londiste.table_info
        set local = true,
            merge_state = new_state
        where queue_name = i_queue_name and table_name = fq_table_name;
    if not found then
        raise exception 'lost table: %', fq_table_name;
    end if;

    -- create trigger if it does not exists already
    logtrg_name := '_londiste_' || i_queue_name;
    perform 1 from pg_catalog.pg_trigger
        where tgrelid = londiste.find_table_oid(fq_table_name)
            and tgname = logtrg_name;
    if not found then
        logtrg := 'create trigger ' || quote_ident(logtrg_name)
            || ' after insert or update or delete on ' || londiste.quote_fqname(fq_table_name)
            || ' for each row execute procedure pgq.sqltriga(' || quote_literal(i_queue_name) || ')';
        execute logtrg;
    end if;

    -- Check that no trigger exists on the target table that will get fired
    -- before londiste one (this could have londiste replicate data
    -- out-of-order
    --
    -- Don't report all the trigger names, 8.3 does not have array_accum
    -- available

    select max(trigger_name)
         into logtrg_previous
         from information_schema.triggers,
              londiste.split_fqname(fq_table_name)
        where event_object_schema = schema_part
            and event_object_table = name_part
            and condition_timing = 'AFTER'
	    and substring(trigger_name from 1 for 10) != '_londiste_'
            and substring(trigger_name from char_length(trigger_name) - 6) != '_logger'
            and trigger_name < logtrg_name;

    if logtrg_previous then
       select 301,
              'Table added: ' || fq_table_name
                              || ', but londiste trigger is not first: '
                              || logtrg_previous
         into ret_code, ret_note;
        return;
    end if;

    select 200, 'Table added: ' || fq_table_name into ret_code, ret_note;
    return;
end;
$$ language plpgsql strict;

