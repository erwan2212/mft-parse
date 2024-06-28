mft-win32.exe /sql f: * -> will dump the whole mft to mft.db3 (the db3 file will be overwriten)<br>
mft-win32.exe f: * -> will dump the whole mft to the console<br>
mft-win32.exe f: test -> will dump the whole mft to the console only for files containing the substring test<br>
<br>
select.ps1 is a powershell example to query the mft.db3<br>
you can download from here system.data.sqlite for powershell : https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki<br>
<br>
Some notes/thoughts:<br>
<br>
<b>FileCreationTime</b> (under windows) is the time that the file was created on a disk partition.<br>
It will be updated if you move a file to a different partition/disk on your computer, but because the content hasn't changed, the LastWriteTime won't be.<br>
So you can end up in a situation where your FileCreationTime is later than your LastWriteTime.<br>
<br>
<b>LastWriteTime</b> is the time that the file content was updated.<br>
<br>
<b>FileChangeTime</b> is the same as LastWriteTime except that it will also be updated when metadata is changed (r/w, acl, etc).<br>
<br>
<b>LastAccessTime</b> cannot be trusted as it can be disabled or not all windows OS's have the same settings here.<br>