# Server_usage_logger


The result stored in mysql looks like below

[root@localhost ~]$ mysql -u root -p
Enter password:
Welcome to the MySQL monitor. Commands end with ; or \g.
Your MySQL connection id is 34
Server version: 5.7.5-m15 MySQL Community Server (GPL)

Copyright (c) 2000, 2014, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> use ltuser;
Reading table information for completion of table and column names
You can turn off this feature to get a quicker startup with -A

Database changed
mysql> show tables;
+------------------+
| Tables_in_ltuser |
+------------------+
| user_tracking |
+------------------+
1 row in set (0.00 sec)

mysql> select * from user_tracking;
+-----+--------------------------------------+-----------------------------------------------------+--------+-------------------------------------------------------+----------------------------+------+----------+--------------+-------------------+
| id | HOST | DESTRO | ARCH | CPU | KERNAL | TIME | USERS | IP | MAC |
+-----+--------------------------------------+-----------------------------------------------------+--------+-------------------------------------------------------+----------------------------+------+----------+--------------+-------------------+
| 1 | localhost | Red Hat Enterprise Linux Server release 7.3 (Maipo) | x86_64 | CPU model: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz | 3.10.0-514.21.2.el7.x86_64 | IST | user | 192.168.1.11 | 10:03:e4:53:22:98 |


