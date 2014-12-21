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
all monit services are in running state (monit summary), avoiding to create
non consistent backups or running two process simultaneously.

The script logs almost everything on _/var/log/scripts_ and also includes
a copy of this logfile within the output tar file.

