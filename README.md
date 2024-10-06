The following command line options are valid:<br>
<br>
--drive=<string>        selected drive/partition to dump mft for - if offline, only used to build paths (default: c:)<br>
--filter=<string>       optional, pattern to filter files<br>
--mft_filename=<string> optional, will use an offline mft dump<br>
--first_record=<int>    optional, first mft record to start enumerating (default: 16)<br>
--last_record=<int>     optional, last mft record to stop enumerating<br>
--db3                   optional, will dump records to mft.db3 sqlite DB<br>
--dr                    optional, will display dataruns i.e clusters used by a file - needs filter flag<br>
--dr_backup             optional, will dump dataruns i.e clusters used by a file - needs dr flag<br>
--dt                    optional, will display deleted files only<br>
--mft_backup            optional, will backup the mft to mft.dmp - not supported in offline mode or if mft is<br>
                        fragmented<br>
<br>
Here below some powershell examples to play with the sqlite DB:<br>
-select.ps1 is a powershell example to query the mft.db3.<br>
-select-BIG25.ps1 will output top 25 biggest files.<br>
-select-OLD25.ps1 will output top 25 oldest files.<br>
-select-SIZEBEFORE2020.ps1 will output the sum of filesizes changed prior to 2020.<br>
-select-SIZEPERYEAR.ps1 will output the sum of filesizes per year.<br>
-select-COMPRESSED.ps1 will display files with flag=compressed.<br>
-select-CSV.ps1 will create a CSV file listing all files prior to 2020 out of the DB3.<br>
-select-delete-file.ps1 will deleted all files prior to 1996 out of the DB3.<br>
you can download from here system.data.sqlite for powershell (recommanded : .net 4.6) : https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki<br>
<br>
Some notes/thoughts:<br>
<br>
If the MFT is <b>fragmented</b>, you will need to backup it with extents-win64 like this: extents-win64.exe f:\\$mft c:\\temp\mft.dmp<br>
Although I recommend the use of extents-win64.exe, you can also backup a fragmented mft the followong way ( a file named _$mft will be created on your folder) : mft-win32.exe --drive=f: --filter=$mft --first_record=0 --last_record=15 --dr --dr_backup<br>
<br>
Then dump the mft like this (skip --db3 if you want to dump to the console) : mft-win32.exe --drive=f: --mft_filename=c:\\temp\mft.dmp --db3 <br>
<br>
If the MFT is <b>not fragmented</b>, then this is as simple as run the following command : mft-win32.exe --drive=f:<br>
<br>
Both <b>MBR</b> and <b>GPT</b> partitions are supported.<br>
<br>
<b>FileCreationTime</b> is the time that the file was created on a disk partition.<br>
It will be updated if you move a file to a different partition/disk on your computer, but because the content hasn't changed, the LastWriteTime won't be.<br>
So you can end up in a situation where your FileCreationTime is later than your FileChangeTime.<br>
<br>
<b>FileChangeTime</b> is the time that the file content was updated. Actually the only field you can really trust.<br>
<br>
<b>LastWriteTime</b> is the same as FileChangeTime except that it will also be updated when metadata is changed (r/w, acl, etc). <br>
This date and time refers to when the MFT record itself was last changed. This date and time field is not displayed to a user.<br>
<br>
<b>LastAccessTime</b> cannot be trusted as it can be disabled and not all windows OS's have the same settings here.<br>
Simply cannot be trusted...<br>
<br>
<b>Beware</b>, datetime is stored as text in db3 using your regional settings : do not use date/time functions against that stored data but use string functions.
Alternative in a future version would be to store dates in ISO8601 format YYYY-MM-DD HH:MM:SS.SSS.
<br><br>
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
<br><br>
<b>Flags</b> is also stored - below the possible values (1 is a file, 3 is a directory...)<br>
<br>
Flag	Description<br>
0x01	Record is in use<br>
0x02	Record is a directory (FileName index present)<br>
0x04	Record is an exension (Set for records in the $Extend directory)<br>
0x08	Special index present (Set for non-directory records containing an index: $Secure, $ObjID, $Quota, $Reparse)<br>
