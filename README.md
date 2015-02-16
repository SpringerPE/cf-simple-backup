cf-simple-backup
================

Simple backup script for a Cloud Foudry environment

About cf-simple-backup
=============================

Warning! This information is about how to perform a manual recover 
of a Cloud Foundry environment.

Assumptions:

 * stemcells are saved and up-to-date
 * manifest.yml is saved and up-to-date.

Also, the backup server has to be on the same network than the nfs blobstore, the
reason is because it will mount the blobstore on the NFS server in RO mode, and
copy the files using `rsync`.


Setup
=====

The script works by reading a configuration file with some variables. You can pass
the configuration file as an argument (`-c`), but the script is able to read
it automatically if one exists with the same name as the program (except the suffix).

So, by creating a links to the script and multiple configuration files with
the same name (only changing the sufix `.sh` into `.conf`) and using different 
variables, is possible to backup different CF environments.

Run the backup
==============

```
# ./cf-simple-backup-test.sh backup
--cf-simple-backup-test.sh 2014-12-21 17:16:03: Targeting and login microbosh 10.10.10.10 ... done!
--cf-simple-backup-test.sh 2014-12-21 17:16:06: Getting bosh status ... ok
--cf-simple-backup-test.sh 2014-12-21 17:16:16: Getting bosh manifest for dev ... cf_manifest_20141221171603.yml
--cf-simple-backup-test.sh 2014-12-21 17:16:19: Locating db and nfs hosts ... done!
--cf-simple-backup-test.sh 2014-12-21 17:16:19: Pinging 10.10.10.11 and 10.10.10.12 ... ok
--cf-simple-backup-test.sh 2014-12-21 17:16:23: Checking if 10.10.10.12:/var/vcap/store is mounted ... ok, not mounted
--cf-simple-backup-test.sh 2014-12-21 17:16:23: Starting DB backup.
--cf-simple-backup-test.sh 2014-12-21 17:16:23: Dumping database ccdb ... done!
--cf-simple-backup-test.sh 2014-12-21 17:16:24: Dumping database uaadb ... done!
--cf-simple-backup-test.sh 2014-12-21 17:16:24: Mounting blobstore 10.10.10.12:/var/vcap/store on /tmp/cf-simple-backup-test.sh_20981 ... done!
--cf-simple-backup-test.sh 2014-12-21 17:16:24: Copying files with rsync ... done!
--cf-simple-backup-test.sh 2014-12-21 17:17:02: Umounting remote blobstore: sudo umount -f /tmp/cf-simple-backup-test.sh_20981 ... done
--cf-simple-backup-test.sh 2014-12-21 17:17:02: Adding extra files: /backups/bin/cf-recovering.txt 
--cf-simple-backup-test.sh 2014-12-21 17:17:02: Creating /backups/dev/cf/cf_test_20141221171603.tgz ... done
```

If something went wrong it will finish with an error (return code not 0) and
it will show the error log. Moreover, the program only performs the backup if 
the CF nfsserver is not mounted on the server.

The script logs almost everything on _/var/log/scripts_ and also includes
a copy of this logfile within the output tar file.


Recovery
========

Notes:
* BOSH_WORKSPACE is a place where you can run the bosh client `bosh` and you have your manifests around.

```
# Gather the IPs of the VMs running postgres and nfs
$ cd BOSH_WORKSPACE
$ bosh vms | awk '/ postgres_| nfs_/{ print $2" --> "$8 }'
nfs_z1/0 --> n.n.n.n
postgres_z1/0 --> n.n.n.n

# Stop all api_worker, api, nfs and uaa services. Note that depending on your installation there could be more (or less) services than listed below.
# (order might be important)
$ bosh deployment ENV/manifests/RELASE_VERSION.yml
$ bosh stop api_z1 --soft
$ bosh stop api_z2 --soft
$ bosh stop api_worker_z1 --soft
$ bosh stop api_worker_z2 --soft
$ bosh stop nfs_z1 --soft
$ bosh stop uaa_z1 --soft
$ bosh stop uaa_z2 --soft

# Log in to nfs server and prepare for restoring the data
$ ssh -l vcap NFS_IP
$ sudo rm -rf /var/vcap/store/*
$ sudo mkdir /var/vcap/store/tmp
$ sudo chown vcap.vcap /var/vcap/store/tmp

# Log in to the backup server and copy the nfs data
$ ssh BACKUP_SERVER
$ rsync -arzhv /backups/ENV/cf/cache/store/ vcap@NFS_IP:/var/vcap/store/tmp

# Log in to the nfs server and copy the data into the correct folder
$ ssh -l vcap NFS_IP
$ sudo mv /var/vcap/store/tmp/* /var/vcap/store/
$ sudo rmdir /var/vcap/store/tmp/

# Log in to the backup server and copy the postgres dumps to the VM running postgres
$ ssh BACKUP_SERVER
$ scp /backups/ENV/cf/cache/dbs/* vcap@POSTGRES_IP:/var/vcap/store/postgres

# Log in to the postgres VM and restore the dumps
$ ssh -l vcap POSTGRES_IP
$ cd /var/vcap/store/postgres
$ sudo /var/vcap/bosh/bin/monit restart postgres  # terminates possible remaining open sessions
$ /var/vcap/packages/postgres/bin/psql -h 127.0.0.1 -p 5524 -U vcap postgres < $POSTGRES_UAADB  # File e.g. 'postgres_20150210110858.dump.uaadb'
$ /var/vcap/packages/postgres/bin/psql -h 127.0.0.1 -p 5524 -U vcap postgres < $POSTGRES_CCDB  # File e.g. 'postgres_20150210110858.dump.ccdb'
$ rm $POSTGRES_UAAB
$ rm $POSTGRES_CCDB

# Start the services again (order might be important)
$ cd BOSH_WORKSPACE
$ bosh start nfs_z1
$ bosh start uaa_z1
$ bosh start uaa_z2
$ bosh start api_z1
$ bosh start api_z2
$ bosh start api_worker_z1
$ bosh start api_worker_z2
```
