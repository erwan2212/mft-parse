program mft;

{$mode objfpc}{$H+}

uses

  windows,sysutils, utils,utilsdb,
  rcmdline in '..\rcmdline-master\rcmdline.pas';



const
  atAttributeStandardInformation = $10;
  atAttributeFileName = $30;
  atAttributeData = $80;

var
  //default value below needed for offline mode
  BytesPerFileRecord: Word=1024;
  BytesPerCluster: Word=4096;
  BytesPerSector: Word=512;
  SectorsPerCluster: Word=8;
  //
  MASTER_FILE_TABLE_LOCATION : Int64;             //    \
  MASTER_FILE_TABLE_END : Int64;                  //     |__    MFT Location & Contents
  MASTER_FILE_TABLE_SIZE : Int64;                 //     |      Information
  MASTER_FILE_TABLE_RECORD_COUNT : int64; //integer;       //    /
  //
  PATHS : array of string;
  CURRENT_DRIVE:string;
  //
  filter:string='';
  drive:string='';
  mft_filename:string='';
  sql:boolean=false;
  dr_backup:boolean=false;
  first_record:longint=16;
  last_record:longint=0;
  //
  hdevice:thandle=thandle(-1);
  dst:thandle=thandle(-1);
  //
  cmd:TCommandLineReader;

  function do_backup(lcn:int64;nbclusters:dword;ClusterSize:word):boolean;
  var
  dwread,dwwritten: dword;
  Buf: array of byte;   //PByte;
  i:longword;
  offset:large_integer;
  i64:int64;
  begin
    //writeln(lcn);writeln(nbclusters);writeln(ClusterSize);
        result:=false;
        //GetMem(Buff, ClusterSize); //allocmem would create a zerofilled buffer
        //buf:=allocmem(ClusterSize ); //not in a loop would be preferrable
        setlength(buf,ClusterSize);
        offset.QuadPart :=lcn*ClusterSize;
        i64:=lcn*ClusterSize;
        //writeln(i64);
        //if SetFilePointer(hdevice, Offset.LowPart, @Offset.HighPart, FILE_BEGIN)=DWORD(-1) then exit;
        if SetFilePointer(hdevice, int64rec(i64).Lo , @int64rec(i64).hi, FILE_BEGIN)=DWORD(-1) then exit;
        for i:=1 to nbclusters do
        begin
        if Readfile(hDevice, buf[0], ClusterSize, dwread, nil)
           then writefile(dst,buf[0],dwread,dwwritten,nil);
        end; //for
        //FreeMem(Buff);
        result:=true;
  end;

  function negative (input:string):longword;
  begin
    case length(input) of
         4:result:=$ffff-strtoint('$'+input)+1; //2 bytes
         6:result:=$ffffff-strtoint('$'+input)+1; //3 bytes
         8:result:=$ffffffff-strtoint('$'+input)+1; //4 bytes
    end;
  end;

function LeftPad(value:integer; length:integer=8; pad:char='0'): string; overload;
begin
   result := RightStr(StringOfChar(pad,length) + IntToStr(value), length );
end;

function LeftPad(value: string; length:integer=8; pad:char='0'): string; overload;
begin
   result := RightStr(StringOfChar(pad,length) + value, length );
end;

procedure FixupUpdateSequence(var RecordData: TDynamicCharArray);
var
  pFileRecord: ^TFILE_RECORD;
  UpdateSequenceOffset, UpdateSequenceCount: Word;
  UpdateSequenceNumber: array[1..2] of Char;
  i: integer;
begin

  New(pFileRecord);
  ZeroMemory(pFileRecord, SizeOf(TFILE_RECORD));
  CopyMemory(pFileRecord, @RecordData[0], SizeOf(TFILE_RECORD));

  with pFileRecord^.Header do begin
    if Identifier[1]+Identifier[2]+Identifier[3]+Identifier[4] <> 'FILE' then
       begin
      Dispose(pFileRecord);
      raise Exception.Create('Unable to Fixup the Update Sequence : Invalid Record Data :'+
                             ' No FILE Identifier found');
    end;
  end;

  UpdateSequenceOffset := pFileRecord^.Header.UsaOffset;
  UpdateSequenceCount := pFileRecord^.Header.UsaCount;

  Dispose(pFileRecord);

  UpdateSequenceNumber[1] := RecordData[UpdateSequenceOffset];
  UpdateSequenceNumber[2] := RecordData[UpdateSequenceOffset+1];

  for i:=1 to UpdateSequenceCount-1 do begin
    // Validity Test
    if  (RecordData[i*BytesPerSector-2] <> UpdateSequenceNumber[1])
    and (RecordData[i*BytesPerSector-1] <> UpdateSequenceNumber[2]) then
        raise Exception.Create('Unable to Fixup the Update Sequence : Invalid Record Data :'+
                               ' Sector n°'+IntToStr(i)+' is corrupt !');

    RecordData[i*BytesPerSector-2] := RecordData[UpdateSequenceOffset+2*i];
    RecordData[i*BytesPerSector-1] := RecordData[UpdateSequenceOffset+1+2*i];
  end;

end;

function FindAttributeByType(RecordData: TDynamicCharArray; AttributeType: DWord;
                                        FindSpecificFileNameSpaceValue: boolean=false;AttributeOffset:pword=nil) : TDynamicCharArray;
  var
    pFileRecord: ^TFILE_RECORD;
    pRecordAttribute: ^TRECORD_ATTRIBUTE;
    NextAttributeOffset: Word;
    TmpRecordData: TDynamicCharArray;
    TotalBytes: Word;
  begin
    New(pFileRecord);
    ZeroMemory(pFileRecord, SizeOf(TFILE_RECORD));
    CopyMemory(pFileRecord, @RecordData[0], SizeOf(TFILE_RECORD));
    if  pFileRecord^.Header.Identifier[1] + pFileRecord^.Header.Identifier[2]
       + pFileRecord^.Header.Identifier[3] + pFileRecord^.Header.Identifier[4]<>'FILE' then
    begin
      NextAttributeOffset := 0; // In this case, the parameter is a buffer taken from a recursive call
    end else
    begin
      NextAttributeOffset := pFileRecord^.AttributesOffset; // Means that it's the first run of recursion
    end;

    TotalBytes := Length(RecordData); // equals to BytesPerFileRecord in the second case (first run)
    Dispose(pFileRecord);

    New(pRecordAttribute);
    ZeroMemory(pRecordAttribute, SizeOf(TRECORD_ATTRIBUTE));

    SetLength(TmpRecordData,TotalBytes-(NextAttributeOffset-1));
    TmpRecordData := Copy(RecordData,NextAttributeOffset,TotalBytes-(NextAttributeOffset-1));
    CopyMemory(pRecordAttribute, @TmpRecordData[0], SizeOf(TRECORD_ATTRIBUTE));

    while (pRecordAttribute^.AttributeType <> $FFFFFFFF) and
          (pRecordAttribute^.AttributeType <> AttributeType) do begin
      NextAttributeOffset := NextAttributeOffset + pRecordAttribute^.Length;
      SetLength(TmpRecordData,TotalBytes-(NextAttributeOffset-1));
      TmpRecordData := Copy(RecordData,NextAttributeOffset,TotalBytes-(NextAttributeOffset-1));
      CopyMemory(pRecordAttribute, @TmpRecordData[0], SizeOf(TRECORD_ATTRIBUTE));
    end;

    if pRecordAttribute^.AttributeType = AttributeType then
       begin
       //writeln(inttohex(AttributeType,1)+' @ '+inttohex(NextAttributeOffset,2));
       if AttributeOffset <>nil then copymemory(AttributeOffset,@NextAttributeOffset,sizeof(word));
      if (FindSpecificFileNameSpaceValue) and (AttributeType=atAttributeFileName)  then
         begin

        // We test here the FileNameSpace Value directly (without any record structure)
        if (TmpRecordData[$59]=Char($0)) {POSIX} or (TmpRecordData[$59]=Char($1)) {Win32}
           or (TmpRecordData[$59]=Char($2))
           or (TmpRecordData[$59]=Char($3)) {Win32&DOS} then
              begin
              SetLength(result,pRecordAttribute^.Length);
              result := Copy(TmpRecordData,0,pRecordAttribute^.Length);
              end
              else
              begin
              NextAttributeOffset := NextAttributeOffset + pRecordAttribute^.Length;
              SetLength(TmpRecordData,TotalBytes-(NextAttributeOffset-1));
              TmpRecordData := Copy(RecordData,NextAttributeOffset,TotalBytes-(NextAttributeOffset-1));
              // Recursive Call : finds next matching attributes
              result := FindAttributeByType(TmpRecordData,AttributeType,true);
              end; //if (TmpRecordData[$59]=Char($0)) {POSIX} ...

              end
              else
              begin
              SetLength(result,pRecordAttribute^.Length);
              result := Copy(TmpRecordData,0,pRecordAttribute^.Length);
              end; //if (FindSpecificFileNameSpaceValue) and (AttributeType=atAttributeFileName)  then

              end
              else
              begin
              result := nil;
              end; //if pRecordAttribute^.AttributeType = AttributeType then
    Dispose(pRecordAttribute);
  end;

function GetFilePath(ReferenceToParentDirectory: Int64): string;
var
  ParentRecordNumber: integer;
  LocalParentReference: Int64;
  ParentName: string;
  //hDevice: THandle;
  dwread: LongWord;
  ParentRecordLocator: Int64;
  MFTData: TDynamicCharArray;
  pFileRecord: ^TFILE_RECORD;
  FileNameAttributeData: TDynamicCharArray;
  pFileNameAttribute : ^TFILENAME_ATTRIBUTE;
begin

  ParentRecordNumber := Int64Rec(ReferenceToParentDirectory).Lo;

  // The MFT may be smaller than it was before,
  // so some file records may refer to parent folders that are now out of range!
  if ParentRecordNumber >= Length(PATHS) then begin
    result := '*';
    exit;
  end else if ParentRecordNumber=5 then begin // The fifth record is the Root Directory of the Hard Drive
    result := CURRENT_DRIVE;
    exit;
  end;

  ParentName := PATHS[ParentRecordNumber];

  if ParentName<>'' then begin
    // If the parent has already been processed, it's no use doing it again!
    result := ParentName;
    exit;

  end
  else
  begin
    // Else, we have to recursively determine the path
    // WARNING: The path may NOT be correct if a directory record has been replaced by another!
    // Any error will lead to answer '*\' which actually means "no way to determine further the parent"


    //hDevice := CreateFile(PChar('\\.\'+CURRENT_DRIVE), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if (hDevice = INVALID_HANDLE_VALUE) then
    begin
      //Closehandle(hDevice);

      //PATHS[ParentRecordNumber] := '*'; // We do NOT record this in the table, because
                                          // there is NOT any record failure : the HDD
                                          // just can't be opened now...
                                          // (even if it is still opened during the research process)
                                          // I actually think this will never happen! But who knows?
      writeln('GetFilePath:INVALID_HANDLE_VALUE');
      result := '*';
      exit;
    end;

    ParentRecordLocator := MASTER_FILE_TABLE_LOCATION + ParentRecordNumber*BytesPerFileRecord;

    // Memory Allocation / Prepares the buffer structure which will contain the File Record
    SetLength(MFTData,BytesPerFileRecord);
    if SetFilePointer(hDevice, Int64Rec(ParentRecordLocator).Lo,@Int64Rec(ParentRecordLocator).Hi, FILE_BEGIN)=DWORD(-1) then
       begin
       PATHS[ParentRecordNumber] := '*';
       result := '*';
       exit;
       end;
    Readfile(hDevice, PChar(MFTData)^, BytesPerFileRecord, dwread, nil);

    try
      FixupUpdateSequence(MFTData);
    except
      //Closehandle(hDevice);
      PATHS[ParentRecordNumber] := '*';
      result := '*';
      exit;
    end;

    New(pFileRecord);
    //ZeroMemory(pFileRecord, SizeOf(TFILE_RECORD));
    CopyMemory(pFileRecord, @MFTData[0], SizeOf(TFILE_RECORD));
    {//flag
    0x01	Record is in use
    0x02	Record is a directory (FileName index present)
    0x04	Record is an exension (Set for records in the $Extend directory)
    0x08	Special index present (Set for non-directory records containing an index: $Secure, $ObjID, $Quota, $Reparse)
    }
    if ((pFileRecord^.Flags<>$2) and (pFileRecord^.Flags<>$3))
       //or (pFileRecord^.Header.Identifier <>'FILE')  //needed??
       then
    //if pFileRecord^.Flags <>$1 then //inuse
    begin // If it is not a directory
      // The parent directory doesn't exist anymore (it has been overlapped)
      Dispose(pFileRecord);
      //Closehandle(hDevice);
      PATHS[ParentRecordNumber] := '*';
      result := '*';
      exit;
    end;
    Dispose(pFileRecord);

    FileNameAttributeData := FindAttributeByType(MFTData, atAttributeFileName, true);
    if FileNameAttributeData<>nil then begin
      New(pFileNameAttribute);
      //ZeroMemory(pFileNameAttribute, SizeOf(TFILENAME_ATTRIBUTE));
      CopyMemory(pFileNameAttribute, @FileNameAttributeData[0], SizeOf(TFILENAME_ATTRIBUTE));
      // Gets the Path Name, which begins at offset $5A of this attribute
         ParentName := WideString(Copy(FileNameAttributeData, $5A, 1+pFileNameAttribute^.NameLength*2));
      // Gets the Local Parent Directory Record Number :
         LocalParentReference := pFileNameAttribute^.DirectoryFileReferenceNumber;
      Dispose(pFileNameAttribute);
    end else begin
      //Closehandle(hDevice);
      PATHS[ParentRecordNumber] := '*';
      result := '*';
      exit;
    end;

    // Recursive Call
    //Closehandle(hDevice);
    PATHS[ParentRecordNumber] := GetFilePath(LocalParentReference)+'\'+ParentName;
    result := PATHS[ParentRecordNumber];

  end;

end;


procedure log(msg:string);
begin
  writeln(msg);
end;

procedure mft_parse(DRIVE:string;filter:string='';bdatarun:boolean=false;bdeleted:boolean=false;backupmft:boolean=false);
var
//{hDevice,}dst : THandle;

pBootSequence: ^TBOOT_SEQUENCE;
pFileRecord: ^TFILE_RECORD;
pStandardInformationAttribute : ^TSTANDARD_INFORMATION;
pMFTNonResidentAttribute : ^TNONRESIDENT_ATTRIBUTE;
pFileNameAttribute : ^TFILENAME_ATTRIBUTE;
pDataAttributeHeader: ^TRECORD_ATTRIBUTE;

dwread,dwwritten:dword;
MFTData: TDynamicCharArray;
StandardInformationAttributeData: TDynamicCharArray;
MFTAttributeData: TDynamicCharArray;
FileNameAttributeData: TDynamicCharArray;
  DataAttributeHeader: TDynamicCharArray;
CurrentRecordCounter: integer;
  CurrentRecordLocator: Int64;

  FileName: WideString;
  FilePath: string;
  FileCreationTime, FileChangeTime,LastWriteTime, LastAccessTime   : TDateTime;
  FileSize,ParentReferenceNo: Int64;
  FileAttributes:dword;
  FileSizeArray : TDynamicCharArray;

  i,count,percentage:integer;
  location,runlen,runoffset:string;
  current,prev,vcn:long;
  tid,datasize:dword;
  bresident:boolean;
  AttributeOffset,contentoffset,p,Flags:word;
  datarun,datalen,dataoffset,j:byte;
  before,after:QWord;
  buf:array of byte;
  //
  //InBuf: TSTARTING_VCN_INPUT_BUFFER;
  //OutBuf: PRETRIEVAL_POINTERS_BUFFER;
  //Bytes: ULONG;
  bIsFileContiguous:boolean=false;
begin
  //debug
  {
  writeln('***************************************');
  log('db3='+BoolToStr(sql));
  log('selected drive='+drive);
  log('filter='+filter);
  log('datarun='+BoolToStr (bdatarun));
  log('deleted='+BoolToStr (bdeleted));
  log('backupmft='+BoolToStr (backupmft));
  log('first_record='+inttostr(first_record));
  log('last_record='+inttostr(last_record));
  log('BytesPerFileRecord='+inttostr(BytesPerFileRecord));
  }
  //
  CURRENT_DRIVE :=drive; //'c:' //global var since used in getfilepath

  //***********************************************************
  //boot sequence : do we need it in offline mode? i'd say not...
  if mft_filename='' then //we are NOT in offline mode
  begin


  hDevice := CreateFile( PChar('\\.\'+CURRENT_DRIVE ), {0}GENERIC_READ, {0}FILE_SHARE_READ or FILE_SHARE_WRITE,
                         nil, OPEN_EXISTING, 0{FILE_FLAG_SEQUENTIAL_SCAN}, 0);
  if (hDevice = INVALID_HANDLE_VALUE) then
  begin
  writeln('INVALID_HANDLE_VALUE,'+inttostr(GetLastError) );
  exit;
  end;

  New(PBootSequence);
  ZeroMemory(PBootSequence, SizeOf(TBOOT_SEQUENCE));
  SetFilePointer(hDevice, 0, nil, FILE_BEGIN);
  ReadFile(hDevice,PBootSequence^, 512,dwread,nil);

  writeln('***************************************');
    with PBootSequence^ do begin
    if  (cOEMID[1]+cOEMID[2]+cOEMID[3]+cOEMID[4] <> 'NTFS') then begin
      Log('Error : This is not a NTFS disk !');
      Dispose(PBootSequence);
      Closehandle(hDevice);
      exit;
    end else begin
      Log('This is a NTFS disk.');
    end;
  end;
  //*************************************
  BytesPerSector := PBootSequence^.wBytesPerSector;
  SectorsPerCluster := PBootSequence^.bSectorsPerCluster;
  BytesPerCluster := SectorsPerCluster * BytesPerSector;
  Log('Bytes Per Sector : '+IntToStr(BytesPerSector));
  Log('Sectors Per Cluster : '+IntToStr(SectorsPerCluster));
  Log('Bytes Per Cluster : '+IntToStr(BytesPerCluster));
  log('Size : '+IntToStr(PBootSequence^.TotalSectors*BytesPerSector)+' bytes');

  // WARNING : ClustersPerFileRecord is a SIGNED hex value which can't be used directly
  //           when the cluster size is larger than the MFT File Record size !
  if (PBootSequence^.ClustersPerFileRecord < $80) then
      BytesPerFileRecord := PBootSequence^.ClustersPerFileRecord * BytesPerCluster
  else
      BytesPerFileRecord := 1 shl ($100 - PBootSequence^.ClustersPerFileRecord);
  Log('Bytes Per File Record : '+IntToStr(BytesPerFileRecord));

  //************************************
  MASTER_FILE_TABLE_LOCATION := PBootSequence^.MftStartLcn * PBootSequence^.wBytesPerSector
                                * PBootSequence^.bSectorsPerCluster;
  Dispose(PBootSequence);

  //********************************************************************************************

  //if mft_filename='' then //we are NOT in offline mode
  //begin

  log('MFT Location : $'+IntToHex(MASTER_FILE_TABLE_LOCATION,2));

  SetLength(MFTData,BytesPerFileRecord);
  SetFilePointer(hDevice, Int64Rec(MASTER_FILE_TABLE_LOCATION).Lo,@Int64Rec(MASTER_FILE_TABLE_LOCATION).Hi, FILE_BEGIN);
  //closehandle(hdevice);
  //hDevice := CreateFile( PChar(CURRENT_DRIVE+'\$MFT' ), {0}GENERIC_READ, {0}FILE_SHARE_READ or FILE_SHARE_WRITE,nil, OPEN_EXISTING, 0, 0);

  Readfile(hDevice, PChar(MFTData)^, BytesPerFileRecord, dwread, nil);
  Log('MFT Data Read : '+IntToStr(dwread)+' Bytes');

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //
  // Fixes Up the MFT MainRecord Update Sequence
  // . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . //
  try
    FixupUpdateSequence(MFTData);
  except on E: Exception do begin
    Log('Error : '+E.Message);
    Closehandle(hDevice);
    exit;
    end;
  end;
  //Log('MFT Data FixedUp');
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //
  MFTAttributeData := FindAttributeByType(MFTData,atAttributeData);

  New(pMFTNonResidentAttribute);
  ZeroMemory(pMFTNonResidentAttribute, SizeOf(TNONRESIDENT_ATTRIBUTE));
  CopyMemory(pMFTNonResidentAttribute, @MFTAttributeData[0], SizeOf(TNONRESIDENT_ATTRIBUTE));



  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //
  // Quickly checks the reliability of the process (if the MFT is sparse, encrypted or compressed all the
  // data structures we're going to deal with are not reliable!)
  // . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . //
  //Log('MFTNonResidentAttribute.Attribute.Flags:'+inttohex(pMFTNonResidentAttribute^.Attribute.Flags,4));
  if (pMFTNonResidentAttribute^.Attribute.Flags = $8000)
     or (pMFTNonResidentAttribute^.Attribute.Flags = $4000)
     or (pMFTNonResidentAttribute^.Attribute.Flags = $0001) then begin
    Log('Error : The MFT is sparse, encrypted or compressed : Unable to continue.');
    Dispose(pMFTNonResidentAttribute);
    exit;
  end;
  // - - - - - -
  //writeln('pMFTNonResidentAttribute^.HighVCN:'+inttostr(pMFTNonResidentAttribute^.HighVCN));
  //writeln('pMFTNonResidentAttribute^.LowVCN:'+inttostr(pMFTNonResidentAttribute^.LowVCN));
  MASTER_FILE_TABLE_SIZE := pMFTNonResidentAttribute^.HighVCN - pMFTNonResidentAttribute^.LowVCN + 1;
                                                             { \_____________ = 0 _____________/ }

  Dispose(pMFTNonResidentAttribute);

  MASTER_FILE_TABLE_END := MASTER_FILE_TABLE_LOCATION + MASTER_FILE_TABLE_SIZE;
  MASTER_FILE_TABLE_RECORD_COUNT := (MASTER_FILE_TABLE_SIZE * BytesPerCluster) div BytesPerFileRecord;
  Log('MFT Size : '+IntToStr(MASTER_FILE_TABLE_SIZE)+' Clusters'+' - '+IntToStr(MASTER_FILE_TABLE_SIZE*BytesPerCluster)+' bytes');
  log('Number of Records : '+IntToStr(MASTER_FILE_TABLE_RECORD_COUNT));
  //log('MFT LowVCN , HighVCN : '+inttostr(pMFTNonResidentAttribute^.LowVCN)+' , '+inttostr(pMFTNonResidentAttribute^.HighVCN )) ;
  //if MASTER_FILE_TABLE_SIZE=pMFTNonResidentAttribute^.HighVCN +1
  if (IsFileContiguous(CURRENT_DRIVE+'\$mft'))=true
     then
       begin
       log('MFT is contiguous');
       bIsFileContiguous:=true;
       end
     else
     begin
     log('Warning : MFT is fragmented, result may be inconsistent');
     log('Recommended : backup mft and work offline');
     end;


  //test - backup mft - mft could be fragmented and we should go thru the run list of $mft...
  //rawcopy could be use to dump a file from the entryid
  if backupmft=true then
  begin
  if bIsFileContiguous=false then
     begin
     log('Cannot dump fragmented mft');
     closehandle(hDevice );
     exit;
     end;
  dst := CreateFile( PChar('mft.dmp' ), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE,
                         nil, CREATE_ALWAYS , FILE_FLAG_SEQUENTIAL_SCAN, 0);
  SetFilePointer(hDevice, Int64Rec(MASTER_FILE_TABLE_LOCATION).Lo,
                 @Int64Rec(MASTER_FILE_TABLE_LOCATION).Hi, FILE_BEGIN);
  setlength(buf,BytesPerCluster);
  for i:=0 to MASTER_FILE_TABLE_SIZE -1 do
  begin
  if Readfile(hDevice, buf[0], BytesPerCluster, dwread, nil)
     then writefile(dst,buf[0],dwread,dwwritten,nil)
     else begin writeln('writefile failed');break;end;
  end;
  closehandle(dst);
  closehandle(hDevice );
  writeln('mft backuped to mft.dmp');
  exit;
  end;

  end; //if mft_filename='' then //we are NOT in offline mode
  //



  //**********************************************************************************


  if (mft_filename<>'') and (FileExists (mft_filename)=true) then  //we ARE in offline mode
     begin
     writeln('Opening '+mft_filename);
     closehandle(hdevice);
     hDevice := CreateFile( pchar(mft_filename), {0}GENERIC_READ, {0}FILE_SHARE_READ , nil, OPEN_EXISTING, 0, 0);
     if hdevice=thandle(-1) then begin writeln('invalid handle,'+inttostr(getlasterror));exit; end;
     MASTER_FILE_TABLE_LOCATION:=0;
     MASTER_FILE_TABLE_SIZE:=GetFileSizeByHandle(hdevice);
     writeln('->Size:'+inttostr(MASTER_FILE_TABLE_SIZE)+ ' bytes');
     MASTER_FILE_TABLE_RECORD_COUNT := (MASTER_FILE_TABLE_SIZE  ) div BytesPerFileRecord;
     log('->Number of Records : '+IntToStr(MASTER_FILE_TABLE_RECORD_COUNT));
     //BytesPerFileRecord:=1024; //we could set this value here
     end; if (mft_filename<>'') and (FileExists (mft_filename)=true) then  //we ARE in offline mode

  writeln('***************************************');

  // Clears and prepares the PATHS array
  PATHS := nil;
  if (1=1) and (bdatarun=false) then //RetrieveDirectoryTree
  begin
    Log('Tree structure requested : Initializing data container...');
    Setlength(PATHS,MASTER_FILE_TABLE_RECORD_COUNT+1);
  end
  else
  begin
    Log('No tree structure requested.');
  end;

    before:=GetTickCount64 ;
  Log('Scanning for files, Please wait...');
  writeln('***************************************');

  if bdatarun =false
     then if sql=false then log('mft_record_no|ParentReferenceNo|fileName|filepath|FileSize|FileCreationTime|FileChangeTime|LastWriteTime|LastAccessTime|CurrentRecordLocator|resident|location|flags');

  // Skips System File Records
  //log( 'Analyzing File Record 16 out of '+IntToStr(MASTER_FILE_TABLE_RECORD_COUNT));

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //
  // Main Loop
  // . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . //

  if last_record=0 then last_record:=MASTER_FILE_TABLE_RECORD_COUNT-1;
  for CurrentRecordCounter := first_record to last_record do //0 if you want $mft etc
  begin

    CurrentRecordLocator := MASTER_FILE_TABLE_LOCATION + CurrentRecordCounter*BytesPerFileRecord;

    // Memory Allocation / Prepares the buffer structure which will contain each File Record
    SetLength(MFTData,BytesPerFileRecord);
    SetFilePointer(hDevice, Int64Rec(CurrentRecordLocator).Lo,@Int64Rec(CurrentRecordLocator).Hi, FILE_BEGIN);
    Readfile(hDevice, PChar(MFTData)^, BytesPerFileRecord, dwread, nil);



    try
      FixupUpdateSequence(MFTData);
    except on E: Exception do
    begin
      if 1=0 then
        Log('Warning : File Record '+IntToStr(CurrentRecordCounter+1)+' out of '
            +IntToStr(MASTER_FILE_TABLE_RECORD_COUNT)+' : '+E.Message);
      continue;
      end;
    end;



    New(pFileRecord);
    //ZeroMemory(pFileRecord, SizeOf(TFILE_RECORD)); //save a few cycles?
    CopyMemory(pFileRecord, @MFTData[0], SizeOf(TFILE_RECORD));


//mft header is usually 56 bytes - offset 20 & 21 i.e (1st) attributeoffset
//followed by attributes
//http://amanda.secured.org/ntfs-mft-record-parsing-parser/
//https://digital-forensics.sans.org/blog/2012/10/15/resident-data-residue-in-ntfs-mft-entries/
    //if pFileRecord^.Flags=word(bdeleted=false) then //$1
    //if pFileRecord^.Flags<>0 then //$1
    //if 1=1 then
    if (bdeleted=false) or ((bdeleted=true) and (pFileRecord^.Flags=0)) then
    begin
      flags:=pFileRecord^.Flags;
      //writeln(pFileRecord^.BytesInUse ); //the whole record size, eventually contains resident data
      //https://docs.microsoft.com/fr-fr/windows/desktop/DevNotes/attribute-list-entry


      //FileNameAttributeData
      FileNameAttributeData := FindAttributeByType(MFTData, atAttributeFileName, true);
      if FileNameAttributeData<>nil then
      begin
        New(pFileNameAttribute);
        //ZeroMemory(pFileNameAttribute, SizeOf(TFILENAME_ATTRIBUTE));
        CopyMemory(pFileNameAttribute, @FileNameAttributeData[0], SizeOf(TFILENAME_ATTRIBUTE));
        ParentReferenceNo:=Int64Rec(pFileNameAttribute^.DirectoryFileReferenceNumber).lo;
        // Gets the File Name, which begins at offset $5A of this attribute
           FileName := WideString(Copy(FileNameAttributeData, $5A,1+ pFileNameAttribute^.NameLength*2));
           // Gets the File Path
           if 1=1 then //RetrieveDirectoryTree //very very costy !
             FilePath := GetFilePath(pFileNameAttribute^.DirectoryFileReferenceNumber)+'\'
           else
             FilePath := '*\';
        Dispose(pFileNameAttribute);
      end
      else // if FileNameAttributeData<>nil then
      begin
        Dispose(pFileRecord);
        continue;
      end;

      //StandardInformationAttributeData
      if (filter='') or ((filter<>'') and (pos(lowercase(filter),lowercase(filename))>0) ) then
      begin
      StandardInformationAttributeData := FindAttributeByType(MFTData, atAttributeStandardInformation);
      if StandardInformationAttributeData<>nil then
      begin
        New(pStandardInformationAttribute);
        //ZeroMemory(pStandardInformationAttribute, SizeOf(TSTANDARD_INFORMATION));
        CopyMemory(pStandardInformationAttribute, @StandardInformationAttributeData[0],SizeOf(TSTANDARD_INFORMATION));
        // Gets Creation & LastChange Times
        //if you move a file to a different partition/disk on your computer,
        //the CreationTime will be updated, but because the content hasn't changed, the LastWriteTime won't be.
        //So you end up in a situation where your CreationTime is later than your LastWriteTime
           FileCreationTime := Int64TimeToDateTime(pStandardInformationAttribute^.CreationTime);
           FileChangeTime := Int64TimeToDateTime(pStandardInformationAttribute^.ChangeTime);
           LastWriteTime := Int64TimeToDateTime(pStandardInformationAttribute^.LastWriteTime);
           LastAccessTime := Int64TimeToDateTime(pStandardInformationAttribute^.LastAccessTime);
           //writeln(pStandardInformationAttribute^.Attribute.Flags) ; compressed/encrypted/sparse?
           //https://www.futurelearn.com/info/courses/introduction-to-malware-investigations/0/steps/147110#:~:text=The%20Standard%20Information%20attribute%20contains,resides%20within%20the%20attribute%20itself.
           FileAttributes:=pStandardInformationAttribute^.FileAttributes ; //compressed/encrypted/sparse...
        Dispose(pStandardInformationAttribute);
      end
      else //if StandardInformationAttributeData<>nil then
      begin
        Dispose(pFileRecord);
        continue;
      end;
      end; //if (filter='') or ((filter<>'') and (pos(lowercase(filter),lowercase(filename))>0) ) then

      //DataAttributeHeader
      //in the case of ADS, there could be another DATA attribute
      //https://digital-forensics.sans.org/blog/2012/10/15/resident-data-residue-in-ntfs-mft-entries/
      if (filter='') or ((filter<>'') and (pos(lowercase(filter),lowercase(filename))>0) ) then
      begin
      DataAttributeHeader := FindAttributeByType(MFTData, atAttributeData,false,@AttributeOffset);
      if DataAttributeHeader<>nil then
      begin
        location:='';
        New(pDataAttributeHeader);
        //ZeroMemory(pDataAttributeHeader, SizeOf(TRECORD_ATTRIBUTE));
        CopyMemory(pDataAttributeHeader, @DataAttributeHeader[0], SizeOf(TRECORD_ATTRIBUTE));
        //writeln(inttohex(ord(DataAttributeHeader[0]),1)); -> $80
        //https://www.writeblocked.org/resources/NTFS_CHEAT_SHEETS.pdf
        //resident attribute header
        if pDataAttributeHeader^.NonResident=0 then
           begin
           CopyMemory(@datasize, @DataAttributeHeader[$10], 4);
           CopyMemory(@contentoffset, @DataAttributeHeader[$14], 2); //usually 24
           location:='0x'+inttohex(CurrentRecordLocator+AttributeOffset+contentoffset,8);
           //writeln(inttohex(CurrentRecordLocator+AttributeOffset+contentoffset,8));
           end;
        //non resident attribute header
        if pDataAttributeHeader^.NonResident=1 then
           begin
           //run list at offset $40
           //writeln(inttohex(CurrentRecordLocator+AttributeOffset+$40,8));
           location:='N/A';
           //datarun has been requested
           if (bdatarun=true) and (pos(lowercase(filter),lowercase(filename))>0) then
           begin
           writeln(filename);
           datarun:=0;p:=0;prev:=0;count:=0;vcn:=0;
           while 1=1  do
           begin
           runlen:='';runoffset:='';
           datarun:=ord(MFTData [AttributeOffset+$40+p]); //ab //$42 -> 4 & 2  lets read 2=clusters lets read 4=lcn
           if (datarun=$ff) or (datarun=0) then break;
           datalen:=datarun shr 4; //hi = a //number of clusters
           dataoffset:=datarun and $f; //lo = b  //lcn
           if (datalen>4) or (dataoffset>4) then begin writeln('invalid datarun:'+inttohex(datarun,1));break;end;
           //writeln(inttohex(datarun,1)+' '+inttostr(datalen)+' '+inttostr(dataoffset));
           //try
           if dataoffset>0 then for j:=dataoffset-1 downto 0 do runlen:=runlen+leftpad(inttohex(ord(MFTData [AttributeOffset+$40+1+j+p]),1),2,'0');
           if datalen>0 then for j:=datalen-1 downto 0 do runoffset:=runoffset+leftpad(inttohex(ord(MFTData [AttributeOffset+$40+1+dataoffset+j+p]),1),2,'0');
           //ff -> signed, 00 -> unsigned
           //if (length(runoffset)=6 ) and (strtoint('$'+copy(runoffset ,1,2))>=$80)
           //    then runoffset :='FF'+runoffset else runoffset :='00'+runoffset;
           //current:=strtoint('$'+runoffset);
           if (strtoint('$'+copy(runoffset ,1,2))>=$80)
              then current:=-negative(runoffset)
              else current:=strtoint('$'+runoffset);
           //high bit (most left) of last byte becoming first byte = 1 -> ff
           //writeln(runoffset+#9+inttostr(strtoint('$'+runoffset)));
           current:=current+prev;
           writeln('#:'+inttostr(count)+#9+'VCN:'+inttostr(vcn)+#9+'LCN:'+inttostr(current)+#9+'Clusters:'+inttostr(strtoint('$'+runlen)));
           vcn:=vcn+strtoint('$'+runlen);
           //finally
           //end;//try
           p:= p+datalen+dataoffset+1 ;
           prev:=current;
           inc(count);
           //backup has been requested
           if dr_backup=true then
              begin

              if dst=thandle(-1) then
                begin
                {$i-}deletefile('_'+ansistring(fileName));{$i+};
                dst := CreateFile(pchar('_'+ansistring(fileName)), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, CREATE_ALWAYS, FILE_FLAG_SEQUENTIAL_SCAN, 0);
                end;
              if do_backup(current,strtoint('$'+runlen),BytesPerCluster)=false then log('do_backup failed');
              end;
           //
           end; //while datarun<>$ff then
           if dst<>thandle(-1) then begin closehandle(dst);dst:=thandle(-1);end;
           end;  //if pos(filter,filename)>0 then
           end;  //if pDataAttributeHeader^.NonResident=1 then
        // Gets the File Size : there is a little trick to prevent us from loading another data structure
        // which would depend on the value of the Non-Resident Flag...
        // A concrete example greatly helps comprehension of the following line !
           //_SwapEndian(Hex($MftFileSize,16)) ; Allocated size
	   //_SwapEndian(Hex($MftFileSize,16)) ; Real size
	   //_SwapEndian(Hex($MftFileSize,16)) ; Initialized size
           FileSizeArray := Copy(DataAttributeHeader, $10+(pDataAttributeHeader^.NonResident)*$20,
                                 (pDataAttributeHeader^.NonResident+$1)*$4 );
           //filesize:= ByteSwap64 (pDataAttribute(@DataAttributeHeader[0])^.DataSize) ;
           FileSize := 0;
           for i:=Length(FileSizeArray)-1 downto 0 do FileSize := (FileSize shl 8)+Ord(FileSizeArray[i]);
           bresident:= pDataAttributeHeader^.NonResident=0 ;
           Dispose(pDataAttributeHeader);
      end
      else //if DataAttributeHeader<>nil then
      begin
        Dispose(pFileRecord);
        continue;
      end;
      end; //if (filter='') or ((filter<>'') and (pos(lowercase(filter),lowercase(filename))>0) ) then

      if bdatarun=false then
      begin
      if (filter<>'') then
         begin
         if (pos(lowercase(filter),lowercase(filename))>0)
            then if sql=false then log(inttostr(pFileRecord^.MFT_Record_No)+'|'+inttostr(ParentReferenceNo)+'|'+fileName+'|'+filepath+'|'+IntToStr(FileSize)+'|'+FormatDateTime('c',FileCreationTime)+'|'+FormatDateTime('c',FileChangeTime)+'|'+FormatDateTime('c',LastWriteTime )+'|'+FormatDateTime('c',LastAccessTime)+'|0x'+inttohex(CurrentRecordLocator,8)+'|'+booltostr(bresident,true)+'|'+location+'|'+inttostr(pFileRecord^.Flags))
                              else insert_db(pFileRecord^.MFT_Record_No,string(fileName),filepath,FileSize,FormatDateTime('c',FileCreationTime),FormatDateTime('c',FileChangeTime),FormatDateTime('c',LastWriteTime),FormatDateTime('c',LastAccessTime),FileAttributes,flags );
         end
         else
         begin
         if sql=false
            then log(inttostr(pFileRecord^.MFT_Record_No)+'|'+inttostr(ParentReferenceNo)+'|'+fileName+'|'+filepath+'|'+IntToStr(FileSize)+'|'+FormatDateTime('c',FileCreationTime)+'|'+FormatDateTime('c',FileChangeTime)+'|'+FormatDateTime('c',LastWriteTime )+'|'+FormatDateTime('c',LastAccessTime)+'|0x'+inttohex(CurrentRecordLocator,8)+'|'+booltostr(bresident,true)+'|'+location+'|'+inttostr(pFileRecord^.Flags))
            else insert_db(pFileRecord^.MFT_Record_No,string(fileName),filepath,FileSize,FormatDateTime('c',FileCreationTime),FormatDateTime('c',FileChangeTime),FormatDateTime('c',LastWriteTime),FormatDateTime('c',LastAccessTime),FileAttributes,flags );
         end;


      end; //if bdatarun=true then

      end;//if pFileRecord^.Flags=$1 then

    Dispose(pFileRecord);

    if sql=true then
      begin
      percentage := Round((CurrentRecordCounter / MASTER_FILE_TABLE_RECORD_COUNT) * 100);
      if (percentage mod 10 = 0) and (percentage <> 0) then SetConsoleTitle(pchar('Progress:'+inttostr(percentage))); //Write('.');
      end;

  end;// for CurrentRecordCounter := 16 to MASTER_FILE_TABLE_RECORD_COUNT-1 do
  if sql=true then writeln;
  after:=GetTickCount64;
  writeln('***************************************');


  //**********************************************************************************
    Log('All File Records Analyzed ('+IntToStr(MASTER_FILE_TABLE_RECORD_COUNT)+') in '+inttostr(after-before)+' ms'  );



  Closehandle(hDevice);
  SetConsoleTitle(pchar('cmd.exe')); //Write('.');
end;



begin


 if paramcount=0 then
 begin
   writeln('https://github.com/erwan2212');
   writeln('Usage: mft-win32 --help');
   exit;
 end;


  cmd := TCommandLineReader.create;
  cmd.declareString('drive', 'selected drive/partition to dump mft for - if offline, only used to build paths','c:');
  cmd.declareString('filter', 'optional, pattern to filter files','');
  cmd.declareString('mft_filename', 'optional, will use an offline mft dump');
  cmd.declareInt ('first_record', 'optional, first mft record to start enumerating',16);
  cmd.declareInt ('last_record', 'optional, last mft record to stop enumerating',0);
  cmd.declareflag('db3', 'optional, will dump records to mft.db3 sqlite DB');
  cmd.declareflag('dr', 'optional, will display dataruns i.e clusters used by a file - needs filter flag');
  cmd.declareflag('dr_backup', 'optional, will dump dataruns i.e clusters used by a file - needs dr flag');
  cmd.declareflag('dt', 'optional, will display deleted files');
  cmd.declareflag('mft_backup', 'optional, will backup the mft to mft.dmp - not supported in offline mode or if mft is fragmented');

  cmd.parse(cmdline);

  drive:=cmd.readString ('drive');
  filter:=cmd.readString ('filter');if filter='*' then filter:='';
  mft_filename:=cmd.readString ('mft_filename');
  sql:=cmd.readFlag ('db3');
  first_record:=cmd.readint ('first_record');
  last_record:=cmd.readint ('last_record');
  dr_backup:=cmd.readFlag ('dr_backup');if mft_filename<>'' then dr_backup:=false;

  if sql=true then if create_db=false then begin writeln ('create_db failed');exit; end;
  mft_parse (drive,filter,cmd.readFlag ('dr'),cmd.readFlag ('dt'),cmd.readFlag ('mft_backup'));
  if sql=true then if close_db=false then begin writeln ('close_db failed');exit; end;

end.
