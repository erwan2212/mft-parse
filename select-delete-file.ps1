# Chemin de la base de données SQLite
$databasePath = Resolve-Path "mft.db3"

# Import the SQLite module
# https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki
Add-Type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll"

# Créer la connexion à la base de données
$connectionString = "Data Source=$dbPath;Version=3;"
$connection = New-Object System.Data.SQLite.SQLiteConnection
$connection.ConnectionString = $connectionString
$connection.Open

# Définir la requête SQL pour récupérer les fichiers avant 1996
$query = @"
SELECT * FROM files WHERE CAST(substr(FileChangeTime, 7, 4) AS INTEGER) < 1996 and flags=1
"@

# Créer une commande SQLite
$command = $connection.CreateCommand()
$command.CommandText = $query

# Exécuter la requête et obtenir les résultats
$reader = $command.ExecuteReader()

# Parcourir les résultats et supprimer les fichiers du système de fichiers
while ($reader.Read()) {
    $filePath = $reader["FilePath"]
    $fileName = $reader["FileName"]
    $fullPath = Join-Path $filePath $fileName
    
    # Vérifier si le fichier existe et le supprimer
    if (Test-Path $fullPath) {
        try {
            Remove-Item $fullPath -Force
            Write-Host "Fichier supprimé : $fullPath"
        } catch {
            Write-Host "Erreur lors de la suppression du fichier : $fullPath - $($_.Exception.Message)"
        }
    } else {
        Write-Host "Fichier non trouvé : $fullPath"
    }
}

# Fermer le lecteur et la connexion
$reader.Close()
$connection.Close()

Write-Host "Opération terminée."
