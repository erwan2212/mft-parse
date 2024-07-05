unit utilsdb;

{$mode objfpc}{$H+}

interface

uses
    sqlite3conn, // Pour la connexion SQLite
    sqldb,       // Pour les composants SQL
    db,          // Pour les opérations de base de données
    SysUtils;

var
    //
  Conn: TSQLite3Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery=nil;

  function insert_db(MFT_Record_No:dword;filename,filepath:string;filesize:int64;FileCreationTime,FileChangeTime,LastWriteTime,LastAccessTime:string;FileAttributes:dword;flags:word):boolean;
  function create_db:boolean;
  function close_db:boolean;

implementation

function insert_db(MFT_Record_No:dword;filename,filepath:string;filesize:int64;FileCreationTime,FileChangeTime,LastWriteTime,LastAccessTime:string;FileAttributes:dword;flags:word):boolean;
var
  //Query: TSQLQuery;
  dummy:dword;
begin
  result:=false;
   //Trans.StartTransaction;
   if query=nil then Query := TSQLQuery.Create(nil);
   Query.Database := Conn;

   // Insertion d'un enregistrement
         Query.SQL.Text := 'INSERT INTO files (MFT_Record_No, FileName, FilePath, FileSize, FileCreationTime, FileChangeTime, LastWriteTime, LastAccessTime, FileAttributes, Flags) ' +
                           'VALUES (:MFT_Record_No, :FileName, :FilePath, :FileSize, :FileCreationTime, :FileChangeTime, :LastWriteTime, :LastAccessTime, :FileAttributes, :Flags)';
         Query.Params.ParamByName('MFT_Record_No').AsInteger := MFT_Record_No;
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

function create_db:boolean;
var
//Query: TSQLQuery;
  dummy:dword;
begin
  {$i-}deletefile('mft.db3'){$i-};
  result:=false;
  try
  Conn := TSQLite3Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Conn.DatabaseName := 'mft.db3';
  Conn.Transaction := Trans;
  Trans.Database := Conn;
  Conn.Open;
  Trans.StartTransaction;
  if query=nil then Query := TSQLQuery.Create(nil);
  Query.Database := Conn;

  Query.SQL.Text := 'CREATE TABLE IF NOT EXISTS files (' +
                    'ID INTEGER PRIMARY KEY, ' +
                    'MFT_Record_No INTEGER, ' +
                    'FileName TEXT, ' +
                    'FilePath TEXT, ' +
                    'FileSize INTEGER, ' +
                    'FileCreationTime TEXT, ' +
                    'FileChangeTime TEXT, ' +
                    'LastWriteTime TEXT, ' +
                    'LastAccessTime TEXT, '+
                    'FileAttributes INTEGER, '+
                    'Flags INTEGER)';
   Query.ExecSQL;
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



end.

