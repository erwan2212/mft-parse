unit utilsdb;

{$mode delphi}{$H+}

interface

uses
    sqlite3conn, // Pour la connexion SQLite
    sqldb,       // Pour les composants SQL
    db,          // Pour les opérations de base de données
    SysUtils,windows;

var
    //
  Conn: TSQLite3Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery=nil;

  function insert_db_wide(MFT_Record_No:dword;ParentReferenceNo:int64;filename,filepath:widestring;filesize:int64;FileCreationTime,FileChangeTime,LastWriteTime,LastAccessTime:string;FileAttributes:dword;flags:word):boolean;
  function insert_db(MFT_Record_No:dword;ParentReferenceNo:int64;filename,filepath:string;filesize:int64;FileCreationTime,FileChangeTime,LastWriteTime,LastAccessTime:string;FileAttributes:dword;flags:word):boolean;
  function create_db(encoding:string=''):boolean;
  function close_db:boolean;
  procedure sqlite_version();

  var
    sqlite3_threadsafe:function():integer;stdcall;

implementation

function insert_db_wide(MFT_Record_No:dword;ParentReferenceNo:int64;filename,filepath:widestring;filesize:int64;FileCreationTime,FileChangeTime,LastWriteTime,LastAccessTime:string;FileAttributes:dword;flags:word):boolean;
var
  //Query: TSQLQuery;
  dummy:dword;
begin
  result:=false;
   //Trans.StartTransaction;
   if query=nil then
      begin
        Query := TSQLQuery.Create(nil);
        Query.Database := Conn;
        end;

   // Insertion d'un enregistrement
         Query.SQL.Text := 'INSERT INTO files (MFT_Record_No, ParentReferenceNo, FileName, FilePath, FileSize, FileCreationTime, FileChangeTime, LastWriteTime, LastAccessTime, FileAttributes, Flags) ' +
                           'VALUES (:MFT_Record_No, :ParentReferenceNo, :FileName, :FilePath, :FileSize, :FileCreationTime, :FileChangeTime, :LastWriteTime, :LastAccessTime, :FileAttributes, :Flags)';
         Query.Params.ParamByName('MFT_Record_No').AsInteger := MFT_Record_No;
         Query.Params.ParamByName('ParentReferenceNo').AsLargeInt := ParentReferenceNo;
         Query.Params.ParamByName('FileName').AswideString := FileName;
         Query.Params.ParamByName('FilePath').AswideString := FilePath;
         Query.Params.ParamByName('FileSize').AsLargeInt  := FileSize;
         Query.Params.ParamByName('FileCreationTime').AsString := FileCreationTime;
         Query.Params.ParamByName('FileChangeTime').AsString := FileChangeTime;
         Query.Params.ParamByName('LastWriteTime').AsString := LastWriteTime;
         Query.Params.ParamByName('LastAccessTime').AsString := LastAccessTime;
         Query.Params.ParamByName('FileAttributes').AsInteger := FileAttributes;
         Query.Params.ParamByName('Flags').AsInteger := Flags;
         try
         Query.ExecSQL;
         except
         on e:exception do writeln(inttostr(MFT_Record_No)+' - '+e.message);
         end;

         // Validation de la transaction
         //Trans.Commit;

    //Query.Free;
   result:=true;
end;

function insert_db(MFT_Record_No:dword;ParentReferenceNo:int64;filename,filepath:string;filesize:int64;FileCreationTime,FileChangeTime,LastWriteTime,LastAccessTime:string;FileAttributes:dword;flags:word):boolean;
var
  //Query: TSQLQuery;
  dummy:dword;
begin
  result:=false;
   //Trans.StartTransaction;
   if query=nil then
      begin
        Query := TSQLQuery.Create(nil);
        Query.Database := Conn;
        end;

   // Insertion d'un enregistrement
         Query.SQL.Text := 'INSERT INTO files (MFT_Record_No, ParentReferenceNo, FileName, FilePath, FileSize, FileCreationTime, FileChangeTime, LastWriteTime, LastAccessTime, FileAttributes, Flags) ' +
                           'VALUES (:MFT_Record_No, :ParentReferenceNo, :FileName, :FilePath, :FileSize, :FileCreationTime, :FileChangeTime, :LastWriteTime, :LastAccessTime, :FileAttributes, :Flags)';
         Query.Prepare;
         Query.Params.ParamByName('MFT_Record_No').AsInteger := MFT_Record_No;
         Query.Params.ParamByName('ParentReferenceNo').AsLargeInt := ParentReferenceNo;
         Query.Params.ParamByName('FileName').AsString := FileName;
         Query.Params.ParamByName('FilePath').AsString := FilePath;
         Query.Params.ParamByName('FileSize').AsLargeInt  := FileSize;
         Query.Params.ParamByName('FileCreationTime').AsString := FileCreationTime;
         Query.Params.ParamByName('FileChangeTime').AsString := FileChangeTime;
         Query.Params.ParamByName('LastWriteTime').AsString := LastWriteTime;
         Query.Params.ParamByName('LastAccessTime').AsString := LastAccessTime;
         Query.Params.ParamByName('FileAttributes').AsInteger := FileAttributes;
         Query.Params.ParamByName('Flags').AsInteger := Flags;
         try
         Query.ExecSQL;
         except
         on e:exception do writeln(inttostr(MFT_Record_No)+' - '+e.message);
         end;

         // Validation de la transaction
         //Trans.Commit;

    //Query.Free;
   result:=true;
end;

{
SQLite does not have a storage class set aside for storing dates and/or times.
Instead, the built-in Date And Time Functions of SQLite are capable of storing dates and times as TEXT, REAL, or INTEGER values:
TEXT as ISO8601 strings ("YYYY-MM-DD HH:MM:SS.SSS").
REAL as Julian day numbers, the number of days since noon in Greenwich on November 24, 4714 B.C. according to the proleptic Gregorian calendar.
INTEGER as Unix Time, the number of seconds since 1970-01-01 00:00:00 UTC.

If you use TEXT storage class to store date and time value, you need to use the ISO8601 string format as follows:
YYYY-MM-DD HH:MM:SS.SSS
... or else dont use date and time functions against the stored data
}

function create_db(encoding:string=''):boolean;
var
//Query: TSQLQuery;
  lib:thandle;
begin
  {$i-}deletefile('mft.db3'){$i-};
  result:=false;
  try
  //init
  Conn := TSQLite3Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  if query=nil then Query := TSQLQuery.Create(nil);
  //config
  Conn.DatabaseName := 'mft.db3';
  Conn.Transaction := Trans;
  Trans.Database := Conn;
  Query.Database := Conn;
  Query.Transaction := Trans; //needed?
  //
  Conn.Open;
  Trans.StartTransaction;

  //sqlite_version;

  //Conn.ExecuteDirect('PRAGMA synchronous = OFF;'); //or normal --> Safety level may not be changed inside a transaction

  //Conn.ExecuteDirect('PRAGMA journal_mode = MEMORY;');   //or OFF

  //chcp 65001 ?
  if encoding<>'' then
     begin
       writeln('setting ENCODING to '+encoding);
       Conn.ExecuteDirect('pragma ENCODING="'+encoding+'";');
     end;

  {
  lib:=loadlibrary('sqlite3.dll');
  sqlite3_threadsafe:=getProcAddress(lib,'sqlite3_threadsafe');
  writeln('sqlite3_threadsafe='+inttostr(sqlite3_threadsafe));
  }

  //Query.SQL.Text := 'DROP TABLE IF EXISTS files;';
  //Query.ExecSQL;
  Conn.ExecuteDirect('DROP TABLE IF EXISTS files;');

  Conn.ExecuteDirect('CREATE TABLE IF NOT EXISTS files (' +
                    'ID INTEGER PRIMARY KEY, ' +
                    'MFT_Record_No INTEGER, ' +
                    'ParentReferenceNo INTEGER, ' +
                    'FileName TEXT, ' +
                    'FilePath TEXT, ' +
                    'FileSize INTEGER, ' +
                    'FileCreationTime TEXT, ' +
                    'FileChangeTime TEXT, ' +
                    'LastWriteTime TEXT, ' +
                    'LastAccessTime TEXT, '+
                    'FileAttributes INTEGER, '+
                    'Flags INTEGER);');

   Trans.Commit;
   //Query.Free;
   writeln('***************************************');
   writeln('database mft.db3 created');
   result:=true;
    except
    on e:exception do writeln(e.message);
    end;

end;

function close_db:boolean;
begin
  result:=false;
  try
  Query.Free;
  trans.Commit ;;
  Conn.Close;
  trans.free;
  Conn.Free;
  writeln('***************************************');
  writeln('database mft.db3 closed');
  result:=true;
  except
    on e:exception do writeln(e.message);
  end;

end;

procedure sqlite_version();
var
  version:string;
begin
  if query=nil then Query := TSQLQuery.Create(nil);
  Query.Database := Conn;


  try
  Query.SQL.Text := 'select sqlite_version();';
  Query.open;

      //
      Version := Query.Fields[0].AsString;
      WriteLn('sqlite_version: ', Version);

      Query.Close;

   writeln('***************************************');
   writeln('database mft.db3 created');

    except
    on e:exception do writeln(e.message);
    end;

end;



end.

