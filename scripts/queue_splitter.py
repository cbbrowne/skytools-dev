#! /usr/bin/env python

"""Puts events into queue specified by field from 'queue_field' config parameter.

Config template::

    [queue_splitter]
    job_name          = queue_splitter_test

    src_db            = dbname=sourcedb_test
    dst_db            = dbname=destdb_test

    pgq_queue_name    = source_queue

    # event fields from  where target queue name is read
    #queue_field       = extra1

    logfile           = ~/log/%(job_name)s.log
    pidfile           = ~/pid/%(job_name)s.pid
    use_skylog        = 0
"""

import sys

import pkgloader
pkgloader.require('skytools', '3.0')

import pgq

class QueueSplitter(pgq.SerialConsumer):
    __doc__ = __doc__

    def __init__(self, args):
        pgq.SerialConsumer.__init__(self, "queue_splitter", "src_db", "dst_db", args)

    def process_remote_batch(self, db, batch_id, ev_list, dst_db):
        cache = {}
        queue_field = self.cf.get('queue_field', 'extra1')
        for ev in ev_list:
            row = [ev.type, ev.data, ev.extra1, ev.extra2, ev.extra3, ev.extra4, ev.time]
            queue = ev.__getattr__(queue_field)
            if queue not in cache:
                cache[queue] = []
            cache[queue].append(row)

        # should match the composed row
        fields = ['type', 'data', 'extra1', 'extra2', 'extra3', 'extra4', 'time']

        # now send them to right queues
        curs = dst_db.cursor()
        for queue, rows in cache.items():
            pgq.bulk_insert_events(curs, rows, fields, queue)

if __name__ == '__main__':
    script = QueueSplitter(sys.argv[1:])
    script.start()

