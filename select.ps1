# Import the SQLite module
# https://system.data.sqlite.org/index.html/doc/trunk/www/downloads-unsup.wiki
#Add-Type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll"
Add-Type -Path ".\sqlite-netFx46-binary-bundle-x64-2015-1.0.119.0\System.Data.SQLite.dll"

# Path to the SQLite database file
$databasePath = Resolve-Path "mft.db3"

# SQL query to execute
$query = "SELECT * FROM files where id=20"

#utf16le
function Execute-SQLiteQuery3 {
    param (
        [string]$databasePath,
        [string]$query
    )

    # Set PowerShell to use UTF-16LE for output
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode

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

    # Convert each row of the DataTable to ensure correct handling of UTF-16LE data
    foreach ($row in $dataTable.Rows) {
        $outputRow = @()
        foreach ($item in $row.ItemArray) {
            # Convert each item to string and handle UTF-16LE characters
            $outputRow += [Text.Encoding]::Unicode.GetString([Text.Encoding]::BigEndianUnicode.GetBytes($item.ToString()))
        }
        # Output the row
        $outputRow -join "`t" | Out-Host
    }

    return $dataTable
}

#utf16
function Execute-SQLiteQuery2 {
    param (
        [string]$databasePath,
        [string]$query
    )

    # Set PowerShell to use UTF-16 for output
    #[Console]::OutputEncoding = [System.Text.Encoding]::Unicode

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

    # Convert each row of the DataTable to ensure correct handling of UTF-16 data
    foreach ($row in $dataTable.Rows) {
        $outputRow = @()
        foreach ($item in $row.ItemArray) {
            # Convert each item to string and handle UTF-16 characters
            $outputRow += [Text.Encoding]::Unicode.GetString([Text.Encoding]::UTF8.GetBytes($item.ToString()))
        }
        # Output the row
        $outputRow -join "`t" | Out-Host
    }

    return $dataTable
}

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
    $connection.Open

    # Create a command to execute the SQL query
    $command = $connection.CreateCommand()
    $command.CommandText = $query

    # Execute the query and load the results into a DataTable
    $adapter = New-Object System.Data.SQLite.SQLiteDataAdapter $command
    $dataTable = New-Object System.Data.DataTable
    $adapter.fill($dataTable)

    # Close the connection
    $connection.Close()

    return $dataTable
}
#$PSDefaultParameterValues['*:Encoding'] = 'utf8'
#[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Execute the query and store the results
$results = Execute-SQLiteQuery -databasePath $databasePath -query $query

# Display the results
# $results | Format-Table -AutoSize
$results 