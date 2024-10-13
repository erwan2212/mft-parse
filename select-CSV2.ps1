# Variables pour la connexion à la base SQLite et le chemin du fichier CSV
$databasePath = Resolve-Path "mft.db3"
$outputCsvPath = "files.csv"

# Charger l'assembly SQLite
#Add-Type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll"
Add-Type -Path ".\sqlite-netFx46-binary-bundle-x64-2015-1.0.119.0\System.Data.SQLite.dll"

# Créer une connexion SQLite
$connectionString = "Data Source=$databasePath;Version=3;"
$connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)

# Ouvrir la connexion
$connection.Open()

# Créer une commande SQL pour sélectionner les données de la table 'files'
$query = "SELECT ID, MFT_Record_No, ParentReferenceNo, FileName, FilePath, FileSize, 
                 FileCreationTime, FileChangeTime, LastWriteTime, LastAccessTime, 
                 FileAttributes, Flags FROM files"
$command = $connection.CreateCommand()
$command.CommandText = $query

# Exécuter la commande et récupérer les résultats dans un DataTable
$adapter = New-Object System.Data.SQLite.SQLiteDataAdapter($command)
$dataset = New-Object System.Data.DataSet
$adapter.Fill($dataset)
$dataTable = $dataset.Tables[0]

# Fermer la connexion à la base de données
$connection.Close()

# Exporter les résultats vers un fichier CSV - encoding UTF8 a voir...
$dataTable | Export-Csv -Path $outputCsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Les données ont été exportées avec succès vers $outputCsvPath"
