mft-win32.exe f: * -> will dump the whole mft to the console<br>
mft-win32.exe f: test -> will dump the whole mft to the console only for files containing the substring test<br>
mft-win32.exe /sql f: * -> will dump the whole mft to mft.db3 (the db3 file will be overwriten)<br>
mft-win32.exe /dt f: * -> will dump the whole mft to the console only for files deleted<br>
mft-win32.exe /dr f: * -> will dump the whole mft to the console with their respective datarun i.e extents on the disk<br>
<br>
select.ps1 is a powershell example to query the mft.db3.<br>
select-BIG25.ps1 will output top 25 biggest files.<br>
select-OLD25.ps1 will output top 25 oldest files.<br>
select-SIZEBEFORE2020.ps1 will output the sum of filesizes changed prior to 2020.<br>
select-SIZEPERYEAR.ps1 will output the sum of filesizes per year.<br>
select-COMPRESSED.ps1 will display files with flag=compressed.<br>
you can download from here system.data.sqlite for powershell (recommanded : .net 4.6) : https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki<br>
<br>
Some notes/thoughts:<br>
<br>
If the MFT is <b>fragmented</b>, you will need to dump it with extents-win64.<br>
Name the file mft.dmp and place it at the root of the drive you want to analyse.<br>
Future versions will handle fragmented MFT's transparently.<br>
<br>
Both <b>MBR</b> and <b>GPT</b> partitions are supported.<br>
<br>
<b>FileCreationTime</b> is the time that the file was created on a disk partition.<br>
It will be updated if you move a file to a different partition/disk on your computer, but because the content hasn't changed, the LastWriteTime won't be.<br>
So you can end up in a situation where your FileCreationTime is later than your FileChangeTime.<br>
<br>
<b>FileChangeTime</b> is the time that the file content was updated.<br>
<br>
<b>LastWriteTime</b> is the same as FileChangeTime except that it will also be updated when metadata is changed (r/w, acl, etc). <br>
This date and time refers to when the MFT record itself was last changed. This date and time field is not displayed to a user.<br>
<br>
<b>LastAccessTime</b> cannot be trusted as it can be disabled and not all windows OS's have the same settings here.<br>
Simply cannot be trusted...<br>
<br>
<b>FileAttributes</b> is also stored - below the possible values<br>
<br>
Value	Description<br>
0x0001	Read only<br>
0x0002	Hidden<br>
0x0004	System<br>
0x0020	Archive<br>
0x0040	Device<br>
0x0080	Normal<br>
0x0100	Temporary<br>
0x0200	Sparse file<br>
0x0400	Reparse point<br>
0x0800	Compressed<br>
0x1000	Offline<br>
0x2000	Content not indexed<br>
0x4000	Encrypted<br>
<br>
