program mft;

{$mode objfpc}{$H+}

uses

  windows,sysutils, utils
  { you can add units after this };

const
  atAttributeStandardInformation = $10;
  atAttributeFileName = $30;
  atAttributeData = $80;

var
  BytesPerFileRecord: Word;
  BytesPerCluster: Word;
  BytesPerSector: Word;
  SectorsPerCluster: Word;
  //
  MASTER_FILE_TABLE_LOCATION : Int64;             //    \
  MASTER_FILE_TABLE_END : Int64;                  //     |__    MFT Location & Contents
  MASTER_FILE_TABLE_SIZE : Int64;                 //     |      Information
  MASTER_FILE_TABLE_RECORD_COUNT : integer;       //    /
  //
  PATHS : array of string;
  CURRENT_DRIVE:string;
  //
  filter:string='';

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
    if Identifier[1]+Identifier[2]+Identifier[3]+Identifier[4] <> 'FILE' then begin
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
                                        FindSpecificFileNameSpaceValue: boolean=false) : TDynamicCharArray;
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
       + pFileRecord^.Header.Identifier[3] + pFileRecord^.Header.Identifier[4]<>'FILE' then begin
      NextAttributeOffset := 0; // In this case, the parameter is a buffer taken from a recursive call
    end else begin
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

    if pRecordAttribute^.AttributeType = AttributeType then begin

      if (FindSpecificFileNameSpaceValue) and (AttributeType=atAttributeFileName)  then begin

        // We test here the FileNameSpace Value directly (without any record structure)
        if (TmpRecordData[$59]=Char($0)) {POSIX} or (TmpRecordData[$59]=Char($1)) {Win32}
           or (TmpRecordData[$59]=Char($3)) {Win32&DOS} then begin
          SetLength(result,pRecordAttribute^.Length);
          result := Copy(TmpRecordData,0,pRecordAttribute^.Length);
        end else begin
          NextAttributeOffset := NextAttributeOffset + pRecordAttribute^.Length;
          SetLength(TmpRecordData,TotalBytes-(NextAttributeOffset-1));
          TmpRecordData := Copy(RecordData,NextAttributeOffset,TotalBytes-(NextAttributeOffset-1));
          // Recursive Call : finds next matching attributes
          result := FindAttributeByType(TmpRecordData,AttributeType,true);
        end;

      end else begin
        SetLength(result,pRecordAttribute^.Length);
        result := Copy(TmpRecordData,0,pRecordAttribute^.Length);
      end;

    end else begin
      result := nil;
    end;
    Dispose(pRecordAttribute);
  end;

function GetFilePath(ReferenceToParentDirectory: Int64): string;
var
  ParentRecordNumber: integer;
  LocalParentReference: Int64;
  ParentName: string;
  hDevice: THandle;
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

  end else begin
    // Else, we have to recursively determine the path
    // WARNING: The path may NOT be correct if a directory record has been replaced by another!
    // Any error will lead to answer '*\' which actually means "no way to determine further the parent"

    hDevice := CreateFile(PChar('\\.\'+CURRENT_DRIVE), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
                          nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if (hDevice = INVALID_HANDLE_VALUE) then begin
      Closehandle(hDevice);
      //PATHS[ParentRecordNumber] := '*'; // We do NOT record this in the table, because
                                          // there is NOT any record failure : the HDD
                                          // just can't be opened now...
                                          // (even if it is still opened during the research process)
                                          // I actually think this will never happen! But who knows?
      result := '*';
      exit;
    end;

    ParentRecordLocator := MASTER_FILE_TABLE_LOCATION + ParentRecordNumber*BytesPerFileRecord;

    // Memory Allocation / Prepares the buffer structure which will contain the File Record
    SetLength(MFTData,BytesPerFileRecord);
    SetFilePointer(hDevice, Int64Rec(ParentRecordLocator).Lo,
                   @Int64Rec(ParentRecordLocator).Hi, FILE_BEGIN);
    Readfile(hDevice, PChar(MFTData)^, BytesPerFileRecord, dwread, nil);

    try
      FixupUpdateSequence(MFTData);
    except
      Closehandle(hDevice);
      PATHS[ParentRecordNumber] := '*';
      result := '*';
      exit;
    end;

    New(pFileRecord);
    ZeroMemory(pFileRecord, SizeOf(TFILE_RECORD));
    CopyMemory(pFileRecord, @MFTData[0], SizeOf(TFILE_RECORD));
    if (pFileRecord^.Flags<>$2) and (pFileRecord^.Flags<>$3) then begin // If it is not a directory
      // The parent directory doesn't exist anymore (it has been overlapped)
      Dispose(pFileRecord);
      Closehandle(hDevice);
      PATHS[ParentRecordNumber] := '*';
      result := '*';
      exit;
    end;
    Dispose(pFileRecord);

    FileNameAttributeData := FindAttributeByType(MFTData, atAttributeFileName, true);
    if FileNameAttributeData<>nil then begin
      New(pFileNameAttribute);
      ZeroMemory(pFileNameAttribute, SizeOf(TFILENAME_ATTRIBUTE));
      CopyMemory(pFileNameAttribute, @FileNameAttributeData[0], SizeOf(TFILENAME_ATTRIBUTE));
      // Gets the Path Name, which begins at offset $5A of this attribute
         ParentName := WideString(Copy(FileNameAttributeData, $5A, pFileNameAttribute^.NameLength*2));
      // Gets the Local Parent Directory Record Number :
         LocalParentReference := pFileNameAttribute^.DirectoryFileReferenceNumber;
      Dispose(pFileNameAttribute);
    end else begin
      Closehandle(hDevice);
      PATHS[ParentRecordNumber] := '*';
      result := '*';
      exit;
    end;

    // Recursive Call
    Closehandle(hDevice);
    PATHS[ParentRecordNumber] := GetFilePath(LocalParentReference)+'\'+ParentName;
    result := PATHS[ParentRecordNumber];

  end;

end;


procedure log(msg:string);
begin
  writeln(msg);
end;

procedure mft_parse(DRIVE:string;filter:string='');
var
hDevice : THandle;

pBootSequence: ^TBOOT_SEQUENCE;
pFileRecord: ^TFILE_RECORD;
pStandardInformationAttribute : ^TSTANDARD_INFORMATION;
pMFTNonResidentAttribute : ^TNONRESIDENT_ATTRIBUTE;
pFileNameAttribute : ^TFILENAME_ATTRIBUTE;
pDataAttributeHeader: ^TRECORD_ATTRIBUTE;

dwread:dword;
MFTData: TDynamicCharArray;
StandardInformationAttributeData: TDynamicCharArray;
MFTAttributeData: TDynamicCharArray;
FileNameAttributeData: TDynamicCharArray;
  DataAttributeHeader: TDynamicCharArray;
CurrentRecordCounter: integer;
  CurrentRecordLocator: Int64;

  FileName: WideString;
  FilePath: string;
  FileCreationTime, FileChangeTime: TDateTime;
  FileSize: Int64;
  FileSizeArray : TDynamicCharArray;

  i:integer;
  sql:string;
  tid:dword;
begin

CURRENT_DRIVE :=drive; //'c:'
  hDevice := CreateFile( PChar('\\.\'+CURRENT_DRIVE ), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
                         nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if (hDevice = INVALID_HANDLE_VALUE) then
  begin
  writeln('INVALID_HANDLE_VALUE');
  exit;
  end;
 //******************************************************
  New(PBootSequence);
  ZeroMemory(PBootSequence, SizeOf(TBOOT_SEQUENCE));
  SetFilePointer(hDevice, 0, nil, FILE_BEGIN);
  ReadFile(hDevice,PBootSequence^, 512,dwread,nil);

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

  log('MFT Location : $'+IntToHex(MASTER_FILE_TABLE_LOCATION,2));



  SetLength(MFTData,BytesPerFileRecord);
  SetFilePointer(hDevice, Int64Rec(MASTER_FILE_TABLE_LOCATION).Lo,
                 @Int64Rec(MASTER_FILE_TABLE_LOCATION).Hi, FILE_BEGIN);
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
  Log('MFT Data FixedUp');
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //
  MFTAttributeData := FindAttributeByType(MFTData,atAttributeData);

  New(pMFTNonResidentAttribute);
  ZeroMemory(pMFTNonResidentAttribute, SizeOf(TNONRESIDENT_ATTRIBUTE));
  CopyMemory(pMFTNonResidentAttribute, @MFTAttributeData[0], SizeOf(TNONRESIDENT_ATTRIBUTE));



  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //
  // Quickly checks the reliability of the process (if the MFT is sparse, encrypted or compressed all the
  // data structures we're going to deal with are not reliable!)
  // . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . //
  if (pMFTNonResidentAttribute^.Attribute.Flags = $8000)
     or (pMFTNonResidentAttribute^.Attribute.Flags = $4000)
     or (pMFTNonResidentAttribute^.Attribute.Flags = $0001) then begin
    Log('Error : The MFT is sparse, encrypted or compressed : Unable to continue.');
    Dispose(pMFTNonResidentAttribute);
    exit;
  end;
  // - - - - - -
  MASTER_FILE_TABLE_SIZE := pMFTNonResidentAttribute^.HighVCN - pMFTNonResidentAttribute^.LowVCN;
                                                             { \_____________ = 0 _____________/ }


  Dispose(pMFTNonResidentAttribute);


  MASTER_FILE_TABLE_END := MASTER_FILE_TABLE_LOCATION + MASTER_FILE_TABLE_SIZE;
  MASTER_FILE_TABLE_RECORD_COUNT := (MASTER_FILE_TABLE_SIZE * BytesPerCluster) div BytesPerFileRecord;
  Log('MFT Size : '+IntToStr(MASTER_FILE_TABLE_SIZE)+' Clusters');
  log('MFT Size : '+IntToStr(MASTER_FILE_TABLE_SIZE*BytesPerCluster)+' bytes');
  log('Number of Records : '+IntToStr(MASTER_FILE_TABLE_RECORD_COUNT));


  // Clears and prepares the PATHS array
  PATHS := nil;

  if 1=1 then //RetrieveDirectoryTreeCB.Checked then
  begin
    Log('Tree structure requested : Initializing data container...');
    Setlength(PATHS,MASTER_FILE_TABLE_RECORD_COUNT+1);
  end
  else
  begin
    Log('No tree structure requested.');
  end;

  //**********************************************************************************

  Log('Scanning for files, Please wait...');

  // Skips System File Records
  //log( 'Analyzing File Record 16 out of '+IntToStr(MASTER_FILE_TABLE_RECORD_COUNT));


  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //
  // Main Loop
  // . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . //
  for CurrentRecordCounter := 16 to MASTER_FILE_TABLE_RECORD_COUNT-1 do begin

    if (CurrentRecordCounter mod 256) = 0 then
    begin // Refreshes File Counter every 256 records
       //log('Analyzing File Record '+IntToStr(CurrentRecordCounter+1)+' out of ' +IntToStr(MASTER_FILE_TABLE_RECORD_COUNT));
    end;

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
    ZeroMemory(pFileRecord, SizeOf(TFILE_RECORD));
    CopyMemory(pFileRecord, @MFTData[0], SizeOf(TFILE_RECORD));



    if pFileRecord^.Flags=$1 then begin //

      StandardInformationAttributeData := FindAttributeByType(MFTData, atAttributeStandardInformation);
      if StandardInformationAttributeData<>nil then begin
        New(pStandardInformationAttribute);
        ZeroMemory(pStandardInformationAttribute, SizeOf(TSTANDARD_INFORMATION));
        CopyMemory(pStandardInformationAttribute, @StandardInformationAttributeData[0],SizeOf(TSTANDARD_INFORMATION));
        // Gets Creation & LastChange Times
           FileCreationTime := Int64TimeToDateTime(pStandardInformationAttribute^.CreationTime);
           FileChangeTime := Int64TimeToDateTime(pStandardInformationAttribute^.ChangeTime);
        Dispose(pStandardInformationAttribute);
      end else begin
        Dispose(pFileRecord);
        continue;
      end;

      FileNameAttributeData := FindAttributeByType(MFTData, atAttributeFileName, true);
      if FileNameAttributeData<>nil then begin
        New(pFileNameAttribute);
        ZeroMemory(pFileNameAttribute, SizeOf(TFILENAME_ATTRIBUTE));
        CopyMemory(pFileNameAttribute, @FileNameAttributeData[0], SizeOf(TFILENAME_ATTRIBUTE));
        // Gets the File Name, which begins at offset $5A of this attribute
           FileName := WideString(Copy(FileNameAttributeData, $5A,1+ pFileNameAttribute^.NameLength*2));
        // Gets the File Path
           if 1=1 then //RetrieveDirectoryTreeCB.Checked then
             FilePath := GetFilePath(pFileNameAttribute^.DirectoryFileReferenceNumber)+'\'
           else
             FilePath := '*\';
        Dispose(pFileNameAttribute);
      end else begin
        Dispose(pFileRecord);
        continue;
      end;

      DataAttributeHeader := FindAttributeByType(MFTData, atAttributeData);
      if DataAttributeHeader<>nil then begin
        New(pDataAttributeHeader);
        ZeroMemory(pDataAttributeHeader, SizeOf(TRECORD_ATTRIBUTE));
        CopyMemory(pDataAttributeHeader, @DataAttributeHeader[0], SizeOf(TRECORD_ATTRIBUTE));
        // Gets the File Size : there is a little trick to prevent us from loading another data structure
        // which would depend on the value of the Non-Resident Flag...
        // A concrete example greatly helps comprehension of the following line !
           FileSizeArray := Copy(DataAttributeHeader, $10+(pDataAttributeHeader^.NonResident)*$20,
                                 (pDataAttributeHeader^.NonResident+$1)*$4 );
           FileSize := 0;
           for i:=Length(FileSizeArray)-1 downto 0 do FileSize := (FileSize shl 8)+Ord(FileSizeArray[i]);
        Dispose(pDataAttributeHeader);
      end else begin
        Dispose(pFileRecord);
        continue;
      end;

      if (filter<>'') then
      begin
      if (pos(lowercase(filter),lowercase(filename))>0) then log(fileName+','+filepath+','+IntToStr(FileSize)+','+FormatDateTime('c',FileCreationTime)+','+FormatDateTime('c',FileCreationTime)+','+inttostr(CurrentRecordLocator));
      end
      else log(fileName+','+filepath+','+IntToStr(FileSize)+','+FormatDateTime('c',FileCreationTime)+','+FormatDateTime('c',FileCreationTime)+','+inttostr(CurrentRecordLocator));

      end;

    Dispose(pFileRecord);



  end;
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - //



  //**********************************************************************************
    Log('All File Records Analyzed ('+IntToStr(MASTER_FILE_TABLE_RECORD_COUNT)+') - Found '  );

  Dispose(PBootSequence);

  Closehandle(hDevice);
end;

begin
  if paramcount=2 then filter:=paramstr(2);
  mft_parse (paramstr(1),filter);
end.

