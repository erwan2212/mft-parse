# Définir le chemin de la base de données SQLite et le nom de la table à exporter
$databasePath = "mft.db3"
$tableName = "files"
$outputCsvPath = "mft.csv"

# https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki
Add-Type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll"

# Créer une connexion à la base de données SQLite
$connectionString = "Data Source=$databasePath;Version=3;"
$connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
$connection.Open()

# Créer une commande pour sélectionner toutes les données de la table
$command = $connection.CreateCommand()
$command.CommandText = "SELECT * FROM $tableName"

# Exécuter la commande et obtenir les résultats
$reader = $command.ExecuteReader()

# Créer un DataTable pour stocker les résultats
$dataTable = New-Object System.Data.DataTable
$dataTable.Load($reader)

# Fermer le lecteur et la connexion
$reader.Close()
$connection.Close()

# Exporter le DataTable vers un fichier CSV
$dataTable | Export-Csv -Path $outputCsvPath -NoTypeInformation

Write-Host "L'exportation vers $outputCsvPath est terminée."
