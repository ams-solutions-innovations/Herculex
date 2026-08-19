[CmdletBinding()]
param(
    [string]$CatalogPath = 'C:\Users\marti\AMS d.o.o\Herculex\assets\data\exercises.json',
    [string]$OutputDirectory = 'C:\Users\marti\OneDrive\Desktop\Slike vaj',
    [ValidateRange(60, 3600)]
    [int]$DelaySeconds = 300,
    [ValidateRange(0, 10000)]
    [int]$MaxImages = 0,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex(
    $true,
    'HerculexExerciseArtworkGeneration',
    [ref]$mutexCreated
)

if (-not $mutexCreated) {
    Write-Output 'Another exercise-artwork generation run is already active.'
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        throw "Exercise catalog was not found: $CatalogPath"
    }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $logPath = Join-Path $OutputDirectory 'generation.log'

    function Write-GenerationLog([string]$Message) {
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
        Write-Output $line
        Add-Content -LiteralPath $logPath -Value $line
    }

    if ($DryRun -and $MaxImages -eq 0) {
        $MaxImages = 1
    }

    $apiKey = $env:OPENAI_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        $apiKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY', 'User')
    }
    if (-not $DryRun -and [string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'OPENAI_API_KEY is not configured. Set it as a Windows user environment variable before the scheduled run.'
    }
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $env:OPENAI_API_KEY = $apiKey
    }

    $imageCli = 'C:\Users\marti\.codex\skills\.system\imagegen\scripts\image_gen.py'
    if (-not (Test-Path -LiteralPath $imageCli)) {
        throw "The bundled image generator was not found: $imageCli"
    }

    $python = (Get-Command python -ErrorAction Stop).Source
    $exercises = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    $generated = 0

    foreach ($exercise in $exercises) {
        $slug = [string]$exercise.slug
        if ([string]::IsNullOrWhiteSpace($slug)) {
            $slug = ([string]$exercise.name).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
        }
        $slug = $slug.Trim('-')
        $outputFile = Join-Path $OutputDirectory "$slug.png"

        if (Test-Path -LiteralPath $outputFile) {
            continue
        }
        if ($MaxImages -gt 0 -and $generated -ge $MaxImages) {
            break
        }

        $target = if ($exercise.bodyPart) { [string]$exercise.bodyPart } else { 'the primary muscles used by the movement' }
        $equipment = if ($exercise.equipment) { [string]$exercise.equipment } else { 'the appropriate equipment' }
        $name = [string]$exercise.name
        $prompt = @"
Use case: scientific-educational
Asset type: exercise-library illustration for a premium fitness tracking mobile app
Primary request: create an original anatomical exercise illustration of $name, using $equipment, performed with technically correct form.
Scene/backdrop: pure white background, no gym environment, no text or labels.
Subject: one athletic, gender-neutral human figure, full body and all exercise equipment visible, pose clearly showing the movement's working position.
Style/medium: clean grayscale anatomical fitness illustration, detailed muscle fibers, charcoal linework and soft gray shading, educational exercise-library artwork.
Muscle highlighting: bright cyan-blue highlights accurately placed on $target and other primary muscles activated by this exact variation; highlights must follow anatomical muscle shapes.
Composition/framing: centered square composition with generous white margins, readable in a mobile exercise card.
Lighting/mood: neutral educational presentation, high clarity, restrained contrast.
Color palette: white background, black and charcoal linework, light and medium gray anatomy shading, cyan-blue activation accents only.
Text (verbatim): none.
Constraints: recognizable $name; anatomically coherent limbs and joints; correct grip, equipment and range of motion for this exact variation; one person only; no logo, watermark, arrows, labels, clothing or scenery.
Avoid: photorealistic skin, colorful gym scene, distorted hands, extra fingers, extra limbs, floating weights, unrelated equipment, incorrect exercise variation, text.
"@

        Write-GenerationLog "Generating $slug ($name)."
        $arguments = @(
            $imageCli,
            'generate',
            '--model', 'gpt-image-2',
            '--prompt', $prompt,
            '--use-case', 'scientific-educational',
            '--size', '1024x1024',
            '--quality', 'medium',
            '--out', $outputFile
        )
        if ($DryRun) {
            $arguments += '--dry-run'
        }

        & $python @arguments
        if ($LASTEXITCODE -eq 0) {
            $generated++
            Write-GenerationLog "Completed $slug."
        } else {
            Write-GenerationLog "Failed $slug (exit code $LASTEXITCODE); continuing after the cooldown."
        }

        if ($MaxImages -eq 0 -or $generated -lt $MaxImages) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    Write-GenerationLog "Run finished. New images: $generated."
}
finally {
    if ($mutexCreated) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
