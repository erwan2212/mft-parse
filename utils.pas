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

  STARTING_VCN_INPUT_BUFFER = record
    StartingVcn: LARGE_INTEGER;
  end;
  PSTARTING_VCN_INPUT_BUFFER = ^STARTING_VCN_INPUT_BUFFER;

  Extent = record
    NextVcn: LARGE_INTEGER;
    Lcn: LARGE_INTEGER;
  end;

  RETRIEVAL_POINTERS_BUFFER = record
    ExtentCount: DWORD;
    StartingVcn: LARGE_INTEGER;
    Extents: array[0..0] of Extent;
  end;
  PRETRIEVAL_POINTERS_BUFFER = ^RETRIEVAL_POINTERS_BUFFER;
  RETRIEVAL_POINTERS_BUFFERS=array of RETRIEVAL_POINTERS_BUFFER;

  const   FSCTL_GET_RETRIEVAL_POINTERS = 589939; //(($00000009) shr 16) or ((28) shr 14) or ((3) shr 2) or (0);

function Int64TimeToDateTime(aFileTime: Int64): TDateTime;

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

end.

