unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, Comctrls,
  SQLite3Conn, SQLDB, DB;

type

  { TForm1 }

  TForm1 = class(TForm)
    procedure FormShow(Sender: TObject);
    procedure TreeViewExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
  private
    Conn: TSQLite3Connection;
    Trans: TSQLTransaction;
    Query: TSQLQuery;
    TreeView: TTreeView;
    procedure LoadFilesFromDatabase(ParentReferenceNo: Integer; ParentNode: TTreeNode);
    procedure InitializeTreeView;
    procedure Cleanup;

  public

  end;

type
  TFileNode = record
    MFT_Record_No: Integer;
    ParentReferenceNo: Integer;
    FileName: String;
  end;

var
  Form1: TForm1;


implementation

{$R *.lfm}

procedure TForm1.LoadFilesFromDatabase(ParentReferenceNo: Integer; ParentNode: TTreeNode);
var
  FileNode: ^TFileNode;
  NewNode: TTreeNode;
begin
  //Query.SQL.Text := 'SELECT MFT_Record_No, ParentReferenceNo, FileName FROM files WHERE ParentReferenceNo = :ParentReferenceNo AND Flags = 3';
  Query.SQL.Text := 'SELECT MFT_Record_No, ParentReferenceNo, FileName FROM files WHERE ParentReferenceNo = :ParentReferenceNo';
  Query.ParamByName('ParentReferenceNo').AsInteger := ParentReferenceNo;
  Query.Open;

  while not Query.EOF do
  begin
    New(FileNode);
    FileNode^.MFT_Record_No := Query.FieldByName('MFT_Record_No').AsInteger;
    FileNode^.ParentReferenceNo := Query.FieldByName('ParentReferenceNo').AsInteger;
    FileNode^.FileName := Query.FieldByName('FileName').AsString;

    if ParentNode = nil then
      NewNode := TreeView.Items.Add(nil, FileNode^.FileName)
    else
      NewNode := TreeView.Items.AddChild(ParentNode, FileNode^.FileName);

    NewNode.Data := FileNode;
    NewNode.HasChildren := True; // Indiquer qu'il peut avoir des enfants (pour lazy loading)

    Query.Next;
  end;

  Query.Close;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  InitializeTreeView;
end;

procedure tform1.TreeViewExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  FileNode: ^TFileNode;
begin
  // Si le noeud a déjà des enfants, ne pas recharger
  if Node.HasChildren and (Node.Count = 0) then
  begin
    FileNode := Node.Data;
    LoadFilesFromDatabase(FileNode^.MFT_Record_No, Node);
  end;
end;

procedure TForm1.InitializeTreeView;
begin
  TreeView := TTreeView.Create(Form1); // Assuming Form1 is your main form
  TreeView.Parent := Form1;
  TreeView.Align := alClient;
  TreeView.OnExpanding := @TreeViewExpanding;

  Conn := TSQLite3Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);

  try
    Conn.DatabaseName := '..\mft.db3';
    Conn.Transaction := Trans;
    Trans.Database := Conn;

    Query.DataBase := Conn;

    Trans.StartTransaction;
    LoadFilesFromDatabase(5, nil); // Charger les noeuds racine avec ParentReferenceNo = 5
    Trans.Commit;
  except
    Trans.Rollback;
    raise;
  end;
end;

procedure TForm1.Cleanup;
begin
  Query.Free;
  Trans.Free;
  Conn.Free;
end;


end.

