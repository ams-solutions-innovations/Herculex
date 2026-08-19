$ErrorActionPreference = 'Stop'

$catalogPath = Join-Path (Get-Location) 'assets/data/exercises.json'
$outputDir = Join-Path (Get-Location) 'outputs/01a00f78-82de-72a3-af89-71d12cb46333'
$outputPath = Join-Path $outputDir 'herculex-vaje.xlsx'
$tempDir = Join-Path $env:TEMP ('herculex-xlsx-' + [guid]::NewGuid().ToString('N'))

if (Test-Path -LiteralPath $outputPath) {
  throw "Output already exists: $outputPath"
}

$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

function XmlEscape([object]$value) {
  if ($null -eq $value) { return '' }
  $text = [string]$value
  return $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function TextValue([object]$value) {
  if ($null -eq $value) { return '' }
  if ($value -is [System.Array]) { return (($value | ForEach-Object { [string]$_ }) -join ', ') }
  return [string]$value
}

function ColumnName([int]$number) {
  $result = ''
  while ($number -gt 0) {
    $remainder = ($number - 1) % 26
    $result = [char](65 + $remainder) + $result
    $number = [math]::Floor(($number - 1) / 26)
  }
  return $result
}

function StringCell([string]$ref, [string]$value, [string]$style = '0') {
  return ('<c r="' + $ref + '" t="inlineStr" s="' + $style + '"><is><t xml:space="preserve">' + (XmlEscape $value) + '</t></is></c>')
}

function NumberCell([string]$ref, [object]$value, [string]$style = '0') {
  return ('<c r="' + $ref + '" s="' + $style + '"><v>' + (XmlEscape $value) + '</v></c>')
}

function RowXml([int]$rowNumber, [object[]]$values, [int[]]$numericIndexes = @(), [int[]]$styleIndexes = @()) {
  $cells = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $values.Count; $i++) {
    $ref = "$(ColumnName ($i + 1))$rowNumber"
    $style = if ($styleIndexes.Count -gt $i) { [string]$styleIndexes[$i] } else { '0' }
    if ($numericIndexes -contains $i) {
      $cells.Add((NumberCell $ref $values[$i] $style))
    } else {
      $cells.Add((StringCell $ref (TextValue $values[$i]) $style))
    }
  }
  return ('<row r="' + $rowNumber + '">' + ($cells -join '') + '</row>')
}

$headers = @(
  'Zap. št.', 'Ime vaje', 'Slug', 'Alias', 'Telesni del', 'Kategorija', 'Vzorec gibanja',
  'Modalnost', 'Oprema', 'Primarna mišica', 'Sekundarne mišice', 'Stabilizatorji',
  'CNS ocena', 'Vpliv na regeneracijo', 'Metrika beleženja', 'Podpira obteženo telesno težo',
  'Privzeti počitek (s)', 'Izpeljana različica'
)

$exerciseRows = New-Object System.Collections.Generic.List[string]
$exerciseRows.Add('<row r="1">' + (StringCell 'A1' 'Herculex — katalog vaj' '1') + '</row>')
$exerciseRows.Add('<row r="2">' + (StringCell 'A2' "Vse vaje in različice, ki so trenutno vključene v assets/data/exercises.json. Skupaj: $($catalog.Count)" '2') + '</row>')
$headerRow = 4
$exerciseRows.Add((RowXml $headerRow $headers @() (1..18 | ForEach-Object { 3 })))

$rowNumber = 5
$index = 1
foreach ($exercise in $catalog) {
  $weighted = if ($exercise.supportsWeightedBodyweight) { 'Da' } else { 'Ne' }
  $derived = if ($exercise.derived) { 'Da' } else { 'Ne' }
  $values = @(
    $index,
    $exercise.name,
    $exercise.slug,
    (TextValue $exercise.aka),
    $exercise.bodyPart,
    $exercise.category,
    $exercise.movementPatternRaw,
    $exercise.modality,
    $exercise.equipment,
    $exercise.primaryMuscle,
    (TextValue $exercise.secondaryMuscles),
    (TextValue $exercise.stabilizers),
    $exercise.cnsScore,
    $exercise.recoveryImpact,
    $exercise.loggingMetric,
    $weighted,
    $exercise.defaultRestSeconds,
    $derived
  )
  $exerciseRows.Add((RowXml $rowNumber $values @(0, 12, 13, 16) (0..17 | ForEach-Object { if ($_ -in @(0, 12, 13, 16)) { 4 } else { 0 } })))
  $rowNumber++
  $index++
}

$summaryRows = New-Object System.Collections.Generic.List[string]
$summaryRows.Add('<row r="1">' + (StringCell 'A1' 'Herculex — povzetek kataloga' '1') + '</row>')
$summaryRows.Add('<row r="3">' + (StringCell 'A3' 'Meritev' '3') + (StringCell 'B3' 'Vrednost' '3') + '</row>')
$summaryRows.Add('<row r="4">' + (StringCell 'A4' 'Skupno število vaj / različic' '0') + (NumberCell 'B4' $catalog.Count '4') + '</row>')
$summaryRows.Add('<row r="5">' + (StringCell 'A5' 'Izpeljane različice' '0') + (NumberCell 'B5' @($catalog | Where-Object derived).Count '4') + '</row>')
$summaryRows.Add('<row r="6">' + (StringCell 'A6' 'Osnovni zapisi' '0') + (NumberCell 'B6' @($catalog | Where-Object { -not $_.derived }).Count '4') + '</row>')

function AddBreakdown([string]$title, [string]$property, [int]$startRow) {
  $rows = New-Object System.Collections.Generic.List[string]
  $rows.Add(('<row r="' + $startRow + '">' + (StringCell ('A' + $startRow) $title '3') + (StringCell ('B' + $startRow) 'Število' '3') + '</row>'))
  $groups = $catalog | Group-Object -Property $property | Sort-Object Name
  $r = $startRow + 1
  foreach ($group in $groups) {
    $rows.Add(('<row r="' + $r + '">' + (StringCell ('A' + $r) $group.Name '0') + (NumberCell ('B' + $r) $group.Count '4') + '</row>'))
    $r++
  }
  return $rows
}

foreach ($line in (AddBreakdown 'Po telesnem delu' 'bodyPart' 9)) { $summaryRows.Add($line) }
$categoryStart = 9 + (@($catalog | Group-Object bodyPart)).Count + 3
foreach ($line in (AddBreakdown 'Po kategoriji' 'category' $categoryStart)) { $summaryRows.Add($line) }
$equipmentStart = $categoryStart + (@($catalog | Group-Object category)).Count + 3
foreach ($line in (AddBreakdown 'Po opremi' 'equipment' $equipmentStart)) { $summaryRows.Add($line) }

$sheet1 = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<dimension ref="A1:R$($rowNumber - 1)"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="18"/><cols><col min="1" max="1" width="9" customWidth="1"/><col min="2" max="2" width="28" customWidth="1"/><col min="3" max="3" width="31" customWidth="1"/><col min="4" max="4" width="25" customWidth="1"/><col min="5" max="9" width="18" customWidth="1"/><col min="10" max="12" width="24" customWidth="1"/><col min="13" max="14" width="14" customWidth="1"/><col min="15" max="15" width="20" customWidth="1"/><col min="16" max="16" width="25" customWidth="1"/><col min="17" max="17" width="19" customWidth="1"/><col min="18" max="18" width="18" customWidth="1"/></cols>
<sheetData>$($exerciseRows -join '')</sheetData>
<autoFilter ref="A4:R$($rowNumber - 1)"/>
</worksheet>
"@

$summaryLastRow = $equipmentStart + (@($catalog | Group-Object equipment)).Count
$sheet2 = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<dimension ref="A1:B$summaryLastRow"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews><sheetFormatPr defaultRowHeight="18"/><cols><col min="1" max="1" width="34" customWidth="1"/><col min="2" max="2" width="16" customWidth="1"/></cols>
<sheetData>$($summaryRows -join '')</sheetData>
</worksheet>
"@

$styles = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Aptos"/></font><font><b/><sz val="16"/><name val="Aptos Display"/></font></fonts>
<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF111827"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0EA5E9"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border/><border><bottom style="thin"><color rgb="FFD1D5DB"/></bottom></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="0" applyAlignment="1"><alignment wrapText="1" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="0" applyFont="1" applyAlignment="1"><font><b/><color rgb="FFFFFFFF"/></font><alignment horizontal="left" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf></cellXfs>
</styleSheet>
"@

$workbook = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets><sheet name="Vse vaje" sheetId="1" r:id="rId1"/><sheet name="Povzetek" sheetId="2" r:id="rId2"/></sheets></workbook>
"@

$contentTypes = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
"@

$rootRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
"@

$workbookRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
"@

$files = @{
  '[Content_Types].xml' = $contentTypes
  '_rels/.rels' = $rootRels
  'xl/workbook.xml' = $workbook
  'xl/_rels/workbook.xml.rels' = $workbookRels
  'xl/styles.xml' = $styles
  'xl/worksheets/sheet1.xml' = $sheet1
  'xl/worksheets/sheet2.xml' = $sheet2
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($entry in $files.GetEnumerator()) {
  $fullPath = Join-Path $tempDir $entry.Key
  $parent = Split-Path -Parent $fullPath
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [System.IO.File]::WriteAllText($fullPath, $entry.Value, $utf8)
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($outputPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($entry in $files.Keys) {
    $source = Join-Path $tempDir $entry
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $source, $entry, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally {
  $zip.Dispose()
}

Remove-Item -LiteralPath $tempDir -Recurse -Force
Write-Output "Created $outputPath with $($catalog.Count) exercises."
