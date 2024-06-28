# Import the SQLite module
# https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki
Add-Type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll"

# Path to the SQLite database file
$databasePath = "mft.db3"

# SQL query to execute
$query = "SELECT *, FileSize / (1024 *1024) as 'MB' FROM files  ORDER BY FileSize DESC LIMIT 25;"

# Function to execute the query and return the results
function Execute-SQLiteQuery {
    param (
        [string]$databasePath,
        [string]$query
    )

    # Create a connection to the SQLite database
    $connectionString = "Data Source=$databasePath;Version=3;"
    $connection = New-Object System.Data.SQLite.SQLiteConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()

    # Create a command to execute the SQL query
    $command = $connection.CreateCommand()
    $command.CommandText = $query

    # Execute the query and load the results into a DataTable
    $adapter = New-Object System.Data.SQLite.SQLiteDataAdapter $command
    $dataTable = New-Object System.Data.DataTable
    $adapter.Fill($dataTable)

    # Close the connection
    $connection.Close()

    return $dataTable
}

# Execute the query and store the results
$results = Execute-SQLiteQuery -databasePath $databasePath -query $query

# Display the results
$results | Format-Table -AutoSize
#$results