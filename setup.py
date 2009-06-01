#! /usr/bin/env python

import sys, os.path, re
from distutils.core import setup
from distutils.extension import Extension

# check if configure has run
if not os.path.isfile('config.mak'):
    print "please run ./configure && make first"
    print "Note: setup.py is supposed to be run from Makefile"
    sys.exit(1)

# load version
buf = open("configure.ac","r").read(256)
m = re.search("AC_INIT[(][^,]*,\s+([^)]*)[)]", buf)
ac_ver = m.group(1)

share_dup_files = [
   'sql/pgq/pgq.sql',
   'sql/londiste/londiste.sql',
   'sql/pgq_ext/pgq_ext.sql',
   'sql/pgq_node/pgq_node.sql',
]
if os.path.isfile('sql/txid/txid.sql'):
   share_dup_files.append('sql/txid/txid.sql')

# run actual setup
setup(
    name = "skytools",
    license = "BSD",
    version = ac_ver,
    maintainer = "Marko Kreen",
    maintainer_email = "markokr@gmail.com",
    url = "http://pgfoundry.org/projects/skytools/",
    package_dir = {'': 'python'},
    packages = ['skytools', 'londiste', 'pgq', 'pgq.cascade'],
    scripts = ['python/londiste.py',
               'python/qadmin.py',
               'python/pgqadm.py',
               'python/walmgr.py',
               'scripts/bulk_loader.py',
               'scripts/cube_dispatcher.py',
               'scripts/queue_loader.py',
               'scripts/queue_mover.py',
               'scripts/queue_splitter.py',
               'scripts/scriptmgr.py',
               'scripts/skytools_upgrade.py',
               'scripts/table_dispatcher.py',
               ],
    data_files = [
      ('share/doc/skytools/conf', [
        'python/conf/wal-master.ini',
        'python/conf/wal-slave.ini',
        ]),
      ('share/skytools', share_dup_files)],
    ext_modules=[Extension("skytools._cquoting", ['python/modules/cquoting.c'])],
)

