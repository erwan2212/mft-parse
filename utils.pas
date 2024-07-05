unit utils;

{$mode objfpc}{$H+}

interface

uses
  windows, SysUtils;

type // This type will be used for containing every array of disk hex data
  TDynamicCharArray = array of Char;

type
  TBOOT_SEQUENCE = packed record
    _jmpcode : array[1..3] of Byte;
   	cOEMID: array[1..8] of Char;
 	  wBytesPerSector: Word;
 	  bSectorsPerCluster: Byte;
    wSectorsReservedAtBegin: Word;
 	  Mbz1: Byte;
 	  Mbz2: Word;
 	  Reserved1: Word;
 	  bMediaDescriptor: Byte;
 	  Mbz3: Word;
 	  wSectorsPerTrack: Word;
 	  wSides: Word;
 	  dwSpecialHiddenSectors: DWord;
 	  Reserved2: DWord;
 	  Reserved3: DWord;
 	  TotalSectors: Int64;
 	  MftStartLcn: Int64;
 	  Mft2StartLcn: Int64;
 	  ClustersPerFileRecord: DWord;
 	  ClustersPerIndexBlock: DWord;
 	  VolumeSerialNumber: Int64;
 	  _loadercode: array[1..430] of Byte;
 	  wSignature: Word;
  end;

//https://docs.microsoft.com/fr-fr/windows/desktop/DevNotes/attribute-record-header
type
  TRECORD_ATTRIBUTE = packed record
    AttributeType : DWord; //0-3
    Length : DWord;        //4-7
    NonResident : Byte;    //8
    NameLength : Byte;     //9
    NameOffset : Word;     //10-11
    Flags : Word;          //12-13
    AttributeNumber : Word; //14-15
  end;

type
  TNONRESIDENT_ATTRIBUTE = packed record
    Attribute: TRECORD_ATTRIBUTE;
    LowVCN: Int64;
    HighVCN: Int64;
    RunArrayOffset : Word;
    CompressionUnit : Byte;
    Padding : array[1..5] of Byte;
    AllocatedSize: Int64;
    DataSize: Int64;
    InitializedSize: Int64;
    CompressedSize: Int64;
  end;



type
  TNTFS_RECORD_HEADER = packed record   //or called MFT header
    Identifier: array[1..4] of Char; // Here must be 'FILE'
    UsaOffset : Word;
    UsaCount : Word;
    LSN : Int64;
  end;

  //https://flatcap.org/linux-ntfs/ntfs/concepts/file_record.html
type
  TFILE_RECORD = packed record
    Header: TNTFS_RECORD_HEADER;
	  SequenceNumber : Word;
	  ReferenceCount : Word;
	  AttributesOffset : Word;
	  Flags : Word; // $0000 = Deleted File,            $0001 = InUse File,
                  // $0002 = Deleted Directory,       $0003 = InUse Directory
	  BytesInUse : DWord;
	  BytesAllocated : DWord;
	  BaseFileRecord : Int64;
	  NextAttributeID : Word;
          dummy:word;
          MFT_Record_No:dword;
  end;

type
  TRESIDENT_ATTRIBUTE = packed record
    Attribute : TRECORD_ATTRIBUTE;
    ValueLength : DWord;
    ValueOffset : Word;
    Flags : Word;
  end;

type
  TFILENAME_ATTRIBUTE = packed record
	  Attribute: TRESIDENT_ATTRIBUTE;
    DirectoryFileReferenceNumber: Int64;
    CreationTime: Int64;
    ChangeTime: Int64;
    LastWriteTime: Int64;
    LastAccessTime: Int64;
    AllocatedSize: Int64;
    DataSize: Int64;
    FileAttributes: DWord;
    AlignmentOrReserved: DWord;
    NameLength: Byte;
    NameType: Byte;
	  Name: Word;
  end;

type
  TSTANDARD_INFORMATION = packed record
	  Attribute: TRESIDENT_ATTRIBUTE;
	  CreationTime: Int64;
	  ChangeTime: Int64;
	  LastWriteTime: Int64;
	  LastAccessTime: Int64;
	  FileAttributes: DWord;
	  Alignment: array[1..3] of DWord;
	  QuotaID: DWord;
	  SecurityID: DWord;
	  QuotaCharge: Int64;
	  USN: Int64;
  end;

  TVCN = Int64;
  TLCN = Int64;

  // Définition de l'extent de récupération des pointeurs
  TRETRIEVAL_POINTERS_BUFFER_EXTENT = record
    NextVcn: TVCN;
    Lcn: TLCN;
  end;

  // Définition de la structure de récupération des pointeurs
  TRETRIEVAL_POINTERS_BUFFER = record
    ExtentCount: DWORD;
    StartingVcn: TVCN;
    Extents: array[0..0] of TRETRIEVAL_POINTERS_BUFFER_EXTENT;
  end;
  PRETRIEVAL_POINTERS_BUFFER = ^TRETRIEVAL_POINTERS_BUFFER;

  // Définition de la structure de l'entrée du VCN de départ
  TSTARTING_VCN_INPUT_BUFFER = record
    StartingVcn: TVCN;
  end;

  const   FSCTL_GET_RETRIEVAL_POINTERS = 589939; //(($00000009) shr 16) or ((28) shr 14) or ((3) shr 2) or (0);

function Int64TimeToDateTime(aFileTime: Int64): TDateTime;
function GetFileSizeByHandle(FileHandle: THandle): Int64;
function IsFileContiguous(const FileName: string): Boolean;

implementation

//=====================================================================================================//
//  Converts  WinFile_Time  into  UTC_Time
//-----------------------------------------------------------------------------------------------------//
function Int64TimeToDateTime(aFileTime: Int64): TDateTime;
var
  UTCTime, LocalTime: TSystemTime;
begin
  FileTimeToSystemTime( TFileTime(aFileTime), UTCTime);
  SystemTimeToTzSpecificLocalTime(nil, UTCTime, LocalTime);
  result := SystemTimeToDateTime(LocalTime);
end;

function GetFileSizeByHandle(FileHandle: THandle): Int64;
var
  FileSizeHigh: DWORD;
  FileSizeLow: DWORD;
begin
  FileSizeLow := GetFileSize(FileHandle, @FileSizeHigh);
  if FileSizeLow = INVALID_FILE_SIZE then
  begin
    Result := -1;
    Exit;
  end;
  Result := (Int64(FileSizeHigh) shl 32) or FileSizeLow;
end;

function IsFileContiguous(const FileName: string): Boolean;
var
  hFile: THandle;
  lpBytesReturned: DWORD;
  StartVcn: TSTARTING_VCN_INPUT_BUFFER;
  BufferSize: DWORD;
  RetrievalPointersBuffer: array of Byte;
  RetPointerBuffer: PRETRIEVAL_POINTERS_BUFFER;
  ExtentCount: DWORD;
  I: Integer;
  CurrentLCN, NextLCN: TLCN;
begin
  Result := False;
  hFile := CreateFile(PChar(FileName), FILE_READ_ATTRIBUTES, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_FLAG_NO_BUFFERING, 0);
  if hFile = INVALID_HANDLE_VALUE then
  begin
    WriteLn('Failed to open file: ', SysErrorMessage(GetLastError));
    Exit;
  end;

  try
    StartVcn.StartingVcn := 0;
    BufferSize := SizeOf(TRETRIEVAL_POINTERS_BUFFER) + 1024 * SizeOf(TRETRIEVAL_POINTERS_BUFFER_EXTENT);
    SetLength(RetrievalPointersBuffer, BufferSize);

    if not DeviceIoControl(hFile, FSCTL_GET_RETRIEVAL_POINTERS, @StartVcn, SizeOf(StartVcn), @RetrievalPointersBuffer[0], BufferSize, @lpBytesReturned, nil) then
    begin
      WriteLn('DeviceIoControl failed: ', SysErrorMessage(GetLastError));
      Exit;
    end;

    RetPointerBuffer := PRETRIEVAL_POINTERS_BUFFER(@RetrievalPointersBuffer[0]);
    ExtentCount := RetPointerBuffer^.ExtentCount;

    if ExtentCount = 1 then
    begin
      Result := True;
      Exit;
    end;

    for I := 0 to ExtentCount - 2 do
    begin
      CurrentLCN := RetPointerBuffer^.Extents[I].Lcn;
      NextLCN := RetPointerBuffer^.Extents[I + 1].Lcn;

      if (NextLCN - CurrentLCN) <> (RetPointerBuffer^.Extents[I + 1].NextVcn - RetPointerBuffer^.Extents[I].NextVcn) then
      begin
        Result := False;
        Exit;
      end;
    end;

    Result := True;
  finally
    CloseHandle(hFile);
  end;
end;




end.

