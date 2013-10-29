/*
This script shows you how to store login credentials for the SYL.
If you're using only trusted connections between your Central instance
and the other instances, you don't need to enter any records into the table.

I use 2 logins:
	Collector's login: minimal permissions necessary to collect the data I need
						or run the necessary operations on the target instances.
	sa login: For use when necessary.
				Most of the environments I worked in has the same sa login on all
				of the servers. I did create a SYL version where specific logins
				are attached to each instance, but it has some other things that
				make it too complex.
				Let's stick with the basics.

Anyway, you are going to have to change the ********* with the real password.
You only need to use it once. The password is then kept encrypted in the SqlLogins
table, and you don't ever have to enter it again. It can only be decrypted inside
the SYL assembly.
*/
use db_cdba
GO
insert into SYL.SqlLogins(SLG_Login, SLG_Password, SLG_IsDefault)
select '<Collector Login Name>', SYL.udf_EncryptPassword('*********'), 1

insert into SYL.SqlLogins(SLG_Login, SLG_Password, SLG_IsDefault)
select 'sa', SYL.udf_EncryptPassword('*********'), 0