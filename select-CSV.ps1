# Chemin de la base de données SQLite
$dbPath = "mft.db3"

# Chemin de sortie pour le fichier CSV
$outputCsvPath = "files.csv"

# Import the SQLite module
# https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki
Add-Type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll"

# Créer la connexion à la base de données
$connectionString = "Data Source=$dbPath;Version=3;"
$connection = New-Object System.Data.SQLite.SQLiteConnection
$connection.ConnectionString = $connectionString
$connection.Open()

# Définir la requête SQL pour récupérer toutes les données de la table "files"
$query = "SELECT * FROM files"

# Créer une commande SQLite
$command = $connection.CreateCommand()
$command.CommandText = $query

# Exécuter la requête et obtenir les résultats
$reader = $command.ExecuteReader()

# Créer un tableau pour stocker les résultats
$data = @()

# Lire les données ligne par ligne
while ($reader.Read()) {
    # Stocker les colonnes de chaque ligne dans un objet PowerShell personnalisé
    $row = New-Object PSObject -Property @{
        ID                = $reader["ID"]
        MFT_Record_No      = $reader["MFT_Record_No"]
        ParentReferenceNo  = $reader["ParentReferenceNo"]
        FileName           = $reader["FileName"]
        FilePath           = $reader["FilePath"]
        FileSize           = $reader["FileSize"]
        FileCreationTime   = $reader["FileCreationTime"]
        FileChangeTime     = $reader["FileChangeTime"]
        LastWriteTime      = $reader["LastWriteTime"]
        LastAccessTime     = $reader["LastAccessTime"]
        FileAttributes     = $reader["FileAttributes"]
        Flags              = $reader["Flags"]
    }

    # Ajouter l'objet au tableau de résultats
    $data += $row
}

# Fermer le lecteur et la connexion
$reader.Close()
$connection.Close()

# Exporter les données au format CSV
$data | Export-Csv -Path $outputCsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Données exportées avec succès vers $outputCsvPath"
