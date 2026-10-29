# =============================================================
# SniperClip - Kit de generation de l'executable autonome
# -------------------------------------------------------------
# Ce script NE MODIFIE PAS vos fichiers sources. Il cree une copie
# adaptee dans build\, puis la compile en dist\SniperClip.exe avec
# ps2exe. Le .exe obtenu est autonome (icone et logo integres) et
# continue d'utiliser %APPDATA%\SniperClip pour ses donnees.
#
# IMPORTANT - ENCODAGE DE CE FICHIER :
#   Enregistrez build.ps1 en "UTF-8 avec BOM"
#   (Bloc-notes : Fichier > Enregistrer sous > Encodage > UTF-8 avec BOM).
#   Un controle automatique s'arrete avec un message si ce n'est pas le cas.
#
# Utilisation, depuis le dossier contenant SniperClip.ps1 :
#   powershell -ExecutionPolicy Bypass -File .\build.ps1 -Sign -SelfSigned
# =============================================================

param(
    [switch]$Sign,        # Signer l'exe apres la compilation
    [switch]$SelfSigned,  # Creer au besoin un certificat auto-signe (confiance locale)
    [string]$Thumbprint   # Empreinte (thumbprint) d'un certificat OV/EV installe
)

$ErrorActionPreference = "Stop"
$AppVersion = "1.0.0.0"       # Version affichee dans les proprietes de l'exe
$CompanyName = "Vincent VELIO"

# -------------------------------------------------------------
# 0. Controle d'encodage de build.ps1 (le fichier doit etre UTF-8 BOM)
# -------------------------------------------------------------
if (([string][char]233) -ne [string]"é") {
    Write-Host "ERREUR : build.ps1 est mal encode." -ForegroundColor Red
    Write-Host "Enregistrez-le en 'UTF-8 avec BOM' :" -ForegroundColor Red
    Write-Host "Bloc-notes > Fichier > Enregistrer sous > Encodage > UTF-8 avec BOM." -ForegroundColor Red
    exit 1
}

# -------------------------------------------------------------
# 1. Localisation des fichiers
# -------------------------------------------------------------
$Root     = $PSScriptRoot
$Src      = Join-Path $Root "SniperClip.ps1"
$Ico      = Join-Path $Root "SniperClip.ico"
$Logo     = Join-Path $Root "SniperClip_logo.png"
$BuildDir = Join-Path $Root "build"
$DistDir  = Join-Path $Root "dist"
$Out      = Join-Path $DistDir "SniperClip.exe"

if (-not (Test-Path -LiteralPath $Src)) {
    Write-Host "ERREUR : SniperClip.ps1 introuvable dans : $Root" -ForegroundColor Red
    Write-Host "Placez build.ps1 dans le dossier contenant SniperClip.ps1." -ForegroundColor Red
    exit 1
}

Write-Host "Source     : $Src"
Write-Host "Icone      : $Ico ($(if (Test-Path -LiteralPath $Ico) {'presente'} else {'ABSENTE'}) )"
Write-Host "Logo       : $Logo ($(if (Test-Path -LiteralPath $Logo) {'present'} else {'absent ( About utilisera l icone )'}) )"

# -------------------------------------------------------------
# 2. Lecture de SniperClip.ps1 (respect de l encodage reel du fichier)
# -------------------------------------------------------------
$bytes = [System.IO.File]::ReadAllBytes($Src)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    Write-Host "Encodage   : UTF-8 avec BOM"
} else {
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $null = $utf8Strict.GetString($bytes)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        Write-Host "Encodage   : UTF-8 sans BOM"
    } catch {
        $text = [System.Text.Encoding]::Default.GetString($bytes)
        Write-Host "Encodage   : ANSI (Windows-1252)"
    }
}
# Normalisation des fins de ligne pour des correctifs fiables.
$text = $text -replace "`r`n", "`n"

# -------------------------------------------------------------
# 2bis. Suppression des caracteres BOM parasites
# -------------------------------------------------------------
# Certains editeurs laissent un ou plusieurs BOM (U+FEFF) invisibles en
# tete de script. Apres compilation, ps2exe ne les retire pas du contenu
# embarque : PowerShell execute alors un jeton invisible colle au
# premier commentaire et affiche l erreur « Le terme « # » n est pas
# reconnu comme nom d applet de commande ». On les supprime ici.
$bomChar = [string][char]0xFEFF
$stripped = 0
while ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1); $stripped++ }
$strayBom = [regex]::Matches($text, [regex]::Escape($bomChar)).Count
if ($strayBom -gt 0) { $text = $text.Replace($bomChar, ""); $stripped += $strayBom }
if ($stripped -gt 0) {
    Write-Host ("Nettoyage : " + $stripped + " caractere(s) BOM parasite supprime(s) du script.") -ForegroundColor Yellow
}
Write-Host ("Premiere ligne du script compile : " + (($text -split "`n")[0]))

# -------------------------------------------------------------
# 3. Correctifs d adaptation au mode exe autonome
# -------------------------------------------------------------
# Chaque correctif remplace un bloc exact du code source dans la COPIE
# compilee uniquement. P1 = dossier reel de l exe + logo integre ;
# P2/P3 = icone et logo de l exe ; P4/P5 = demarrage Windows et
# redemarrage apres import, qui ciblent l exe au lieu du .vbs ;
# P6 = coherence du raccourci demarrage avec l exe reellement lance ;
# P7 = journalisation des erreurs non gerees ; P8 a P12 = Jump List
# de la barre des taches (cellules non vierges, 10 max, plus recentes d abord).

$patches = @(
    @{
        Name = "P1 - Dossier reel de l executable"
        Mandatory = $true
        Old = @'
$AppName = "SniperClip"
$DataDir = Join-Path $env:APPDATA $AppName
'@
        New = @'
# --- Mode autonome (genere par build.ps1) : dossier reel de l executable ---
$script:IsCompiledBuild = $true
$script:LogoB64 = ""
try {
    $script:AppDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} catch { $script:AppDir = "" }
if ([string]::IsNullOrEmpty($script:AppDir)) { $script:AppDir = $PSScriptRoot }
$AppName = "SniperClip"
$DataDir = Join-Path $env:APPDATA $AppName
'@
    },
    @{
        Name = "P2 - Icone fenetre et systray depuis l exe"
        Mandatory = $true
        Old = @'
try {
    $iconPath = Join-Path $PSScriptRoot "SniperClip.ico"
    if(Test-Path -LiteralPath $iconPath){
        $script:appIcon = New-Object System.Drawing.Icon($iconPath)
        $form.Icon = $script:appIcon
    }
} catch { $script:appIcon = $null }
'@
        New = @'
try {
    if ($script:IsCompiledBuild) {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $script:appIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        $form.Icon = $script:appIcon
    } else {
        $iconPath = Join-Path $script:AppDir "SniperClip.ico"
        if (Test-Path -LiteralPath $iconPath) {
            $script:appIcon = New-Object System.Drawing.Icon($iconPath)
            $form.Icon = $script:appIcon
        }
    }
} catch { $script:appIcon = $null }
'@
    },
    @{
        Name = "P3 - Logo integre dans la fenetre About"
        Mandatory = $false
        Old = @'
        try {
            $logoPath = Join-Path $PSScriptRoot "SniperClip_logo.png"
            if(Test-Path -LiteralPath $logoPath){
                $pic.Image = [System.Drawing.Image]::FromFile($logoPath)
            } elseif($null -ne $script:appIcon){
                $pic.Image = $script:appIcon.ToBitmap()
            }
        } catch {}
'@
        New = @'
        try {
            $logoLoaded = $false
            if (-not [string]::IsNullOrEmpty($script:LogoB64)) {
                try {
                    $logoBytes = [Convert]::FromBase64String($script:LogoB64)
                    $logoStream = New-Object System.IO.MemoryStream(,$logoBytes)
                    $pic.Image = [System.Drawing.Image]::FromStream($logoStream)
                    $logoLoaded = $true
                } catch { $logoLoaded = $false }
            }
            if (-not $logoLoaded) {
                $logoPath = Join-Path $script:AppDir "SniperClip_logo.png"
                if (Test-Path -LiteralPath $logoPath) {
                    $pic.Image = [System.Drawing.Image]::FromFile($logoPath)
                } elseif ($null -ne $script:appIcon) {
                    $pic.Image = $script:appIcon.ToBitmap()
                }
            }
        } catch {}
'@
    },
    @{
        Name = "P4a - Demarrage Windows : cible du raccourci"
        Mandatory = $true
        Old = @'
function Set-StartupEnabled([bool]$enabled) {
    try {
        $vbs = Join-Path $PSScriptRoot "Lancer SniperClip.vbs"
        if($enabled){
            if(-not (Test-Path -LiteralPath $vbs)){
                throw "Le fichier 'Lancer SniperClip.vbs' est introuvable dans le dossier de SniperClip."
            }
'@
        New = @'
function Set-StartupEnabled([bool]$enabled) {
    try {
        $vbs = Join-Path $script:AppDir "Lancer SniperClip.vbs"
        if($enabled){
            if($script:IsCompiledBuild){
                $shortcutTarget = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                $shortcutArgs = ""
            } else {
                if(-not (Test-Path -LiteralPath $vbs)){
                    throw "Le fichier 'Lancer SniperClip.vbs' est introuvable dans le dossier de SniperClip."
                }
                $shortcutTarget = Join-Path $env:WINDIR "System32\wscript.exe"
                $shortcutArgs = '//B //NoLogo "' + $vbs + '"'
            }
'@
    },
    @{
        Name = "P4b - Demarrage Windows : proprietes du raccourci"
        Mandatory = $true
        Old = @'
            $ws = New-Object -ComObject WScript.Shell
            $shortcut = $ws.CreateShortcut($script:StartupShortcut)
            $shortcut.TargetPath = Join-Path $env:WINDIR "System32\wscript.exe"
            $shortcut.Arguments = '//B //NoLogo "' + $vbs + '"'
            $shortcut.WorkingDirectory = $PSScriptRoot
            $icon = Join-Path $PSScriptRoot "SniperClip.ico"
'@
        New = @'
            $ws = New-Object -ComObject WScript.Shell
            $shortcut = $ws.CreateShortcut($script:StartupShortcut)
            $shortcut.TargetPath = $shortcutTarget
            $shortcut.Arguments = $shortcutArgs
            $shortcut.WorkingDirectory = $script:AppDir
            $icon = Join-Path $script:AppDir "SniperClip.ico"
'@
    },
    @{
        Name = "P6 - Demarrage Windows : verification de la cible du raccourci"
        Mandatory = $false
        Old = @'
function Get-StartupEnabled {
    try {
        # La nouvelle méthode est la référence.
        if(Test-Path -LiteralPath $script:StartupShortcut){ return $true }
        return $false
    } catch { return $false }
}
'@
        New = @'
function Get-StartupEnabled {
    try {
        # La nouvelle méthode est la référence.
        if(-not (Test-Path -LiteralPath $script:StartupShortcut)){ return $false }
        # En mode exe : le raccourci doit viser l exécutable en cours.
        # Un raccourci obsolète (ancien chemin, époque du .vbs) est ignoré :
        # l option apparaît décochée et la recocher recrée un lien valide.
        if($script:IsCompiledBuild){
            try {
                $ws = New-Object -ComObject WScript.Shell
                $lnk = $ws.CreateShortcut($script:StartupShortcut)
                $target = [string]$lnk.TargetPath
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($lnk)
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ws)
                $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                if($target -and ($target -ieq $exePath)){ return $true }
                return $false
            } catch { return $false }
        }
        return $true
    } catch { return $false }
}
'@
    },
    @{
        Name = "P5a - Redemarrage apres import : chemin a relancer"
        Mandatory = $true
        Old = @'
if($script:restartRequested){
    try {
        $vbs=Join-Path $PSScriptRoot "Lancer SniperClip.vbs"
        if(Test-Path -LiteralPath $vbs){
'@
        New = @'
if($script:restartRequested){
    try {
        $relaunchPath = $null
        if($script:IsCompiledBuild){
            try { $relaunchPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $relaunchPath = $null }
        } else {
            $relaunchPath = Join-Path $script:AppDir "Lancer SniperClip.vbs"
            if (-not (Test-Path -LiteralPath $relaunchPath)) { $relaunchPath = $null }
        }
        if($relaunchPath){
'@
    },
    @{
        Name = "P5b - Redemarrage apres import : lancement"
        Mandatory = $true
        Old = @'
            $wscript=Join-Path $env:WINDIR "System32\wscript.exe"
            $quotedVbs='"'+$vbs.Replace('"','\"')+'"'
            Start-Process -FilePath $wscript -ArgumentList @('//B','//NoLogo',$quotedVbs) -WindowStyle Hidden -WorkingDirectory $PSScriptRoot | Out-Null
'@
        New = @'
            if($script:IsCompiledBuild){
                Start-Process -FilePath $relaunchPath -WindowStyle Hidden -WorkingDirectory $script:AppDir | Out-Null
            } else {
                $wscript=Join-Path $env:WINDIR "System32\wscript.exe"
                $quotedVbs='"'+$relaunchPath.Replace('"','\"')+'"'
                Start-Process -FilePath $wscript -ArgumentList @('//B','//NoLogo',$quotedVbs) -WindowStyle Hidden -WorkingDirectory $script:AppDir | Out-Null
            }
'@
    },
    @{
        Name = "P7 - Journalisation des erreurs non gerees"
        Mandatory = $false
        Old = @'
function Write-SniperClipLog([string]$message,[string]$level="INFO") {
    try { Add-Content -LiteralPath $script:LogFile -Value ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")+" [$level] "+$message) -Encoding UTF8 } catch {}
}
'@
        New = @'
function Write-SniperClipLog([string]$message,[string]$level="INFO") {
    try { Add-Content -LiteralPath $script:LogFile -Value ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")+" [$level] "+$message) -Encoding UTF8 } catch {}
}

# P7 : capture des erreurs non gerees dans le journal de diagnostic.
# Objectif : diagnostiquer les erreurs aleatoires (par ex. op_Subtraction) en
# enregistrant la pile complete dans le journal, au lieu d une simple boite de dialogue.
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({ param($sender2,$e2)
        try {
            Write-SniperClipLog ("Erreur interface : " + $e2.Exception.GetType().FullName + " : " + $e2.Exception.Message) "ERROR"
            Write-SniperClipLog ($e2.Exception.StackTrace) "ERROR"
        } catch {}
    })
    [System.AppDomain]::CurrentDomain.add_UnhandledException({ param($sender2,$e2)
        try {
            $exObj=$e2.ExceptionObject
            if($null -ne $exObj){
                Write-SniperClipLog ("Erreur non geree : " + $exObj.GetType().FullName + " : " + $exObj.Message) "ERROR"
                if($null -ne $exObj.StackTrace){ Write-SniperClipLog ($exObj.StackTrace) "ERROR" }
            }
        } catch {}
    })
} catch {}
'@
    },
    @{
        Name = "P8 - Parametre Task pour la Jump List"
        Mandatory = $false
        Old = @'
# SniperClip V5.48e - application Windows + SQLite
'@
        New = @'
param([string]$Task = "")
# SniperClip V5.48e - application Windows + SQLite
'@
    },
    @{
        Name = "P9 - Instance unique : taches envoyees par la Jump List"
        Mandatory = $false
        Old = @'
        $existing=[SniperClipInstanceGuard]::FindWindow($null,"SniperClip")
        if($existing -ne [IntPtr]::Zero){ [SniperClipInstanceGuard]::ShowWindow($existing,9) | Out-Null; [SniperClipInstanceGuard]::SetForegroundWindow($existing) | Out-Null }
        [System.Environment]::Exit(0)
'@
        New = @'
        if($Task -like "cell:*"){
            $pendingDir=Join-Path $env:APPDATA "SniperClip"
            if(-not (Test-Path -LiteralPath $pendingDir)){ New-Item -ItemType Directory -Force -Path $pendingDir | Out-Null }
            Set-Content -LiteralPath (Join-Path $pendingDir "task.pending") -Value $Task -Encoding ASCII
            [System.Environment]::Exit(0)
        }
        $existing=[SniperClipInstanceGuard]::FindWindow($null,"SniperClip")
        if($existing -ne [IntPtr]::Zero){ [SniperClipInstanceGuard]::ShowWindow($existing,9) | Out-Null; [SniperClipInstanceGuard]::SetForegroundWindow($existing) | Out-Null }
        [System.Environment]::Exit(0)
'@
    },
    @{
        Name = "P10 - Jump List barre des taches (cellules non vierges)"
        Mandatory = $false
        Old = @'
# Raccourcis clavier globaux
'@
        New = @'
# P10 : Jump List Windows (clic droit sur l icone de la barre des taches).
# Liste jusqu a 10 cellules non vierges, de la plus recemment modifiee a la
# moins recente. Cliquer une cellule copie son contenu dans le presse-papiers.
$script:JumpListAppId="SniperClip.Velio"
$script:CellOrderFile=Join-Path $DataDir "cellorder.json"
$script:CellOrder=@()
try {
    if(Test-Path -LiteralPath $script:CellOrderFile){
        $script:CellOrder=@((Get-Content -LiteralPath $script:CellOrderFile -Raw | ConvertFrom-Json) | ForEach-Object { [int]$_ })
    }
} catch { $script:CellOrder=@() }

function Update-CellOrder([int]$idx){
    try {
        $script:CellOrder=@(@($idx)+@($script:CellOrder | Where-Object { $_ -ne $idx })) | Select-Object -First 30
        ConvertTo-Json -InputObject ([int[]]@($script:CellOrder)) | Set-Content -LiteralPath $script:CellOrderFile -Encoding UTF8
    } catch { Write-SniperClipLog ("Mise a jour de l ordre des cellules impossible : " + $_.Exception.Message) "WARN" }
}

$sniperClipJumpCs = 'using System;
using System.Runtime.InteropServices;
using System.Text;

public static class SniperClipJumpList {
    [StructLayout(LayoutKind.Explicit)]
    public struct PROPVARIANT {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pwszVal;
        [FieldOffset(16)] public IntPtr pad2;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY {
        public Guid fmtid;
        public int pid;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore {
        [PreserveSig] int GetCount(out uint cProps);
        [PreserveSig] int GetAt(uint iProp, out PROPERTYKEY key);
        [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        [PreserveSig] int Commit();
    }

    [ComImport]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellLinkW {
        [PreserveSig] int GetPath(StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        [PreserveSig] int GetIDList(out IntPtr pidl);
        [PreserveSig] int SetIDList(IntPtr pidl);
        [PreserveSig] int GetDescription(StringBuilder pszName, int cch);
        [PreserveSig] int SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        [PreserveSig] int GetWorkingDirectory(StringBuilder pszDir, int cch);
        [PreserveSig] int SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        [PreserveSig] int GetArguments(StringBuilder pszArgs, int cch);
        [PreserveSig] int SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        [PreserveSig] int GetHotkey(out ushort hotkey);
        [PreserveSig] int SetHotkey(ushort hotkey);
        [PreserveSig] int GetShowCmd(out int showCmd);
        [PreserveSig] int SetShowCmd(int showCmd);
        [PreserveSig] int GetIconLocation(StringBuilder pszIconPath, int cch, out int iconIndex);
        [PreserveSig] int SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iconIndex);
        [PreserveSig] int SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string relPath, uint reserved);
        [PreserveSig] int Resolve(IntPtr hwnd, uint flags);
        [PreserveSig] int SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport]
    [Guid("0000010B-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPersistFile {
        [PreserveSig] int GetClassID(out Guid pClassID);
        [PreserveSig] int IsDirty();
        [PreserveSig] int Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        [PreserveSig] int Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
        [PreserveSig] int SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        [PreserveSig] int GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [ComImport]
    [Guid("92CA9DCD-5622-4BBA-A805-5E9F541BD8C9")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IObjectArray {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, ref Guid riid, out IntPtr item);
    }

    [ComImport]
    [Guid("5632B1A4-E38A-400A-928A-D4CD63230295")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IObjectCollection {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, ref Guid riid, out IntPtr item);
        [PreserveSig] int AddObject([MarshalAs(UnmanagedType.IUnknown)] object item);
        [PreserveSig] int AddFromArray(IObjectArray source);
        [PreserveSig] int RemoveObjectAt(uint index);
        [PreserveSig] int Clear();
    }

    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    [ClassInterface(ClassInterfaceType.None)]
    public class CShellLink { }

    [ComImport]
    [Guid("6332DEBF-87B5-4670-90C0-5E57B408A49E")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ICustomDestinationList {
        [PreserveSig] int SetAppID([MarshalAs(UnmanagedType.LPWStr)] string appId);
        [PreserveSig] int BeginList(out uint maxSlots, ref Guid riid, out IntPtr removed);
        [PreserveSig] int AppendCategory([MarshalAs(UnmanagedType.LPWStr)] string category, IObjectArray items);
        [PreserveSig] int AppendKnownCategory(int category);
        [PreserveSig] int AddUserTasks(IObjectArray items);
        [PreserveSig] int CommitList();
        [PreserveSig] int GetRemovedDestinations(ref Guid riid, out IntPtr ppv);
        [PreserveSig] int DeleteList([MarshalAs(UnmanagedType.LPWStr)] string appId);
        [PreserveSig] int AbortList();
    }

    [DllImport("propsys.dll", CharSet = CharSet.Unicode)]
    private static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, out IPropertyStore store);

    [DllImport("ole32.dll")]
    private static extern int CoCreateInstance(ref Guid clsid, IntPtr inner, uint context, ref Guid uuid, out IntPtr objOut);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string appId);

    public static bool SetProcessAppId(string appId) {
        try {
            return SetCurrentProcessExplicitAppUserModelID(appId) == 0;
        } catch { return false; }
    }

    public static bool SetLnkAppId(string lnkPath, string appId) {
        try {
            object lo = new CShellLink();
            IPersistFile pf = (IPersistFile)lo;
            int hr = pf.Load(lnkPath, 2);
            if (hr != 0) { return false; }
            IPropertyStore store = (IPropertyStore)lo;
            PROPERTYKEY key = new PROPERTYKEY();
            key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE4D436");
            key.pid = 5;
            PROPVARIANT pv = new PROPVARIANT();
            pv.vt = 31;
            pv.pwszVal = Marshal.StringToCoTaskMemUni(appId);
            hr = store.SetValue(ref key, ref pv);
            int hrC = store.Commit();
            Marshal.FreeCoTaskMem(pv.pwszVal);
            if (hr != 0 || hrC != 0) { return false; }
            int hrS = pf.Save(lnkPath, true);
            if (hrS != 0) { return false; }
            return true;
        } catch { return false; }
    }

    private static object CreateComObject(Guid clsid, uint context) {
        Guid iidUnk = new Guid("00000000-0000-0000-C000-000000000046");
        IntPtr ptr;
        int hr = CoCreateInstance(ref clsid, IntPtr.Zero, context, ref iidUnk, out ptr);
        if (hr != 0) { return null; }
        try {
            return Marshal.GetObjectForIUnknown(ptr);
        } finally { Marshal.Release(ptr); }
    }

    private static readonly Guid IID_PropertyStore = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    private static readonly Guid IID_ObjectArray = new Guid("92CA9DCD-5622-4BBA-A805-5E9F541BD8C9");
    private static readonly Guid CLSID_DestinationList = new Guid("77F10CF0-3DB5-4966-B520-B7C54FD35ED6");
    private static readonly Guid CLSID_ShellLink = new Guid("00021401-0000-0000-C000-000000000046");
    private static readonly Guid CLSID_ObjectCollection = new Guid("2D3468C1-36A7-43B6-AC24-D3F02FD9607A");

    public static bool SetWindowAppId(IntPtr hwnd, string appId) {
        try {
            IPropertyStore store;
            Guid iidPs = IID_PropertyStore;
            int hr = SHGetPropertyStoreForWindow(hwnd, ref iidPs, out store);
            if (hr != 0 || store == null) { return false; }
            PROPERTYKEY key = new PROPERTYKEY();
            key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE4D436");
            key.pid = 5;
            PROPVARIANT pv = new PROPVARIANT();
            pv.vt = 31;
            pv.pwszVal = Marshal.StringToCoTaskMemUni(appId);
            store.SetValue(ref key, ref pv);
            store.Commit();
            Marshal.FreeCoTaskMem(pv.pwszVal);
            return true;
        } catch { return false; }
    }

    public static string UpdateJumpList(string appId, string[] paths, string[] arguments, string[] descriptions, string iconLocation, bool neutralTitles, int variant) {
        string[] res = new string[1];
        res[0] = "thread impossible [JL15]";
        try {
            System.Threading.Thread t = new System.Threading.Thread(() => {
                res[0] = UpdateJumpListCore(appId, paths, arguments, descriptions, iconLocation, neutralTitles, variant);
            });
            t.SetApartmentState(System.Threading.ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            if (!t.Join(15000)) { return "timeoutCOM [JL15]"; }
        } catch (Exception ex) {
            return "exception " + ex.GetType().Name + " : " + ex.Message + " [JL15]";
        }
        return res[0];
    }

    private static string UpdateJumpListCore(string appId, string[] paths, string[] arguments, string[] descriptions, string iconLocation, bool neutralTitles, int variant) {
        try {
            string icon = iconLocation;
            if (variant == 1 || variant == 4) { icon = ""; }
            if (variant == 2) { icon = System.IO.Path.Combine(Environment.SystemDirectory, "shell32.dll"); }
            int n = paths.Length;
            if (n > 10) { n = 10; }
            uint maxSlots = 0;
            if (n == 0) {
                int hrVide = TryList(appId, new object[0], 0, true, out maxSlots);
                if (hrVide != 0) { return "CommitList " + Hr(hrVide) + " [JL15]"; }
                return "aucune cellule";
            }
            object[] links = new object[n];
            for (int i = 0; i < n; i++) {
                string title = descriptions[i];
                if (neutralTitles) { title = "Cellule " + (i + 1); }
                string err = CreateLink(paths[i], arguments[i], title, icon, variant, out links[i]);
                if (err.Length > 0) { return err; }
            }
            int hrTasks = TryList(appId, links, 0, true, out maxSlots);
            if (hrTasks == 0) { return ""; }
            return "AddUserTasks " + Hr(hrTasks) + " taches=" + n + " max=" + ((int)maxSlots) + " [JL15]";
        } catch (Exception ex) {
            return "exception " + ex.GetType().Name + " : " + ex.Message + " [JL15]";
        }
    }

    public static int ProbeTask(string appId, string path, string args, string title, string icon, int variant) {
        int[] res = new int[1];
        res[0] = -101;
        try {
            System.Threading.Thread t = new System.Threading.Thread(() => {
                res[0] = ProbeTaskCore(appId, path, args, title, icon, variant);
            });
            t.SetApartmentState(System.Threading.ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            if (!t.Join(8000)) { res[0] = -100; }
        } catch { res[0] = -101; }
        return res[0];
    }

    private static int ProbeTaskCore(string appId, string path, string args, string title, string icon, int variant) {
        object linkObj;
        string err = CreateLink(path, args, title, icon, variant, out linkObj);
        if (err.Length > 0) { return -102; }
        object[] links = new object[1];
        links[0] = linkObj;
        uint maxSlots;
        return TryList(appId, links, 0, false, out maxSlots);
    }

    public static int ProbeRecent(string appId) {
        int[] res = new int[1];
        res[0] = -101;
        try {
            System.Threading.Thread t = new System.Threading.Thread(() => {
                uint maxSlots;
                res[0] = TryList(appId, new object[0], 2, true, out maxSlots);
            });
            t.SetApartmentState(System.Threading.ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            if (!t.Join(8000)) { res[0] = -100; }
        } catch { res[0] = -101; }
        return res[0];
    }

    public static int ProbeTaskLite(string appId, string path, string args, string title, string icon, int mode) {
        int[] res = new int[1];
        res[0] = -101;
        try {
            System.Threading.Thread t = new System.Threading.Thread(() => {
                res[0] = ProbeTaskLiteCore(appId, path, args, title, icon, mode);
            });
            t.SetApartmentState(System.Threading.ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            if (!t.Join(8000)) { res[0] = -100; }
        } catch { res[0] = -101; }
        return res[0];
    }

    private static int ProbeTaskLiteCore(string appId, string path, string args, string title, string icon, int mode) {
        try {
            object lo = new CShellLink();
            if (lo == null) { return -102; }
            IShellLinkW link = (IShellLinkW)lo;
            int hr = link.SetPath(path);
            if (hr != 0) { return -102; }
            if (mode == 2 && !string.IsNullOrEmpty(args)) {
                hr = link.SetArguments(args);
                if (hr != 0) { return -102; }
            }
            if (mode == 3 && !string.IsNullOrEmpty(icon)) {
                hr = link.SetIconLocation(icon, 0);
                if (hr != 0) { return -102; }
            }
            IPropertyStore store = (IPropertyStore)lo;
            PROPERTYKEY key = new PROPERTYKEY();
            key.fmtid = new Guid("F29F85E0-4FF9-1068-AB91-08002B27B3D9");
            key.pid = 2;
            PROPVARIANT pv = new PROPVARIANT();
            pv.vt = 31;
            pv.pwszVal = Marshal.StringToCoTaskMemUni(title);
            hr = store.SetValue(ref key, ref pv);
            Marshal.FreeCoTaskMem(pv.pwszVal);
            if (hr != 0) { return -102; }
            hr = store.Commit();
            if (hr != 0) { return -102; }
            object[] links = new object[1];
            links[0] = lo;
            uint maxSlots;
            string app = appId;
            if (mode == 0) { app = null; }
            return TryList(app, links, 0, false, out maxSlots);
        } catch { return -102; }
    }

    private static string CreateLink(string path, string args, string title, string icon, int variant, out object linkObj) {
        linkObj = null;
        object lo = new CShellLink();
        if (lo == null) { return "creation ShellLink impossible [JL15]"; }
        IShellLinkW link = (IShellLinkW)lo;
        bool setArgs = (variant != 4);
        bool setDesc = (variant != 4 && variant != 5);
        bool setTitle = (variant != 3);
        bool setIcon = (variant != 1 && variant != 4) && !string.IsNullOrEmpty(icon);
        int hr = link.SetPath(path);
        if (hr != 0) { return "SetPath " + Hr(hr) + " [JL15]"; }
        if (setArgs) {
            hr = link.SetArguments(args);
            if (hr != 0) { return "SetArguments " + Hr(hr) + " [JL15]"; }
        }
        if (setDesc) {
            hr = link.SetDescription(title);
            if (hr != 0) { return "SetDescription " + Hr(hr) + " [JL15]"; }
        }
        if (setIcon) {
            hr = link.SetIconLocation(icon, 0);
            if (hr != 0) { return "SetIconLocation " + Hr(hr) + " [JL15]"; }
        }
        if (setTitle) {
            IPropertyStore store = null;
            try { store = (IPropertyStore)lo; } catch { }
            if (store == null) { return "IPropertyStore indisponible [JL15]"; }
            PROPERTYKEY key = new PROPERTYKEY();
            key.fmtid = new Guid("F29F85E0-4FF9-1068-AB91-08002B27B3D9");
            key.pid = 2;
            string val = title;
            if (string.IsNullOrEmpty(val)) { val = "Cellule"; }
            PROPVARIANT pv = new PROPVARIANT();
            pv.vt = 31;
            pv.pwszVal = Marshal.StringToCoTaskMemUni(val);
            hr = store.SetValue(ref key, ref pv);
            if (hr != 0) { Marshal.FreeCoTaskMem(pv.pwszVal); return "SetTitle " + Hr(hr) + " [JL15]"; }
            hr = store.Commit();
            if (hr != 0) { Marshal.FreeCoTaskMem(pv.pwszVal); return "TitleCommit " + Hr(hr) + " [JL15]"; }
            Marshal.FreeCoTaskMem(pv.pwszVal);
        }
        linkObj = lo;
        return "";
    }

    private static int TryList(string appId, object[] links, int mode, bool commit, out uint maxSlots) {
        maxSlots = 0;
        object listObj = CreateComObject(CLSID_DestinationList, 1);
        if (listObj == null) { return -1; }
        ICustomDestinationList list = (ICustomDestinationList)listObj;
        int hr = 0;
        if (!string.IsNullOrEmpty(appId)) {
            hr = list.SetAppID(appId);
            if (hr != 0) { return hr; }
        }
        Guid iidArray = IID_ObjectArray;
        IntPtr removed;
        hr = list.BeginList(out maxSlots, ref iidArray, out removed);
        if (hr != 0) { return hr; }
        if (removed != IntPtr.Zero) { Marshal.Release(removed); }
        if (mode == 2) {
            hr = list.AppendKnownCategory(2);
        } else if (links.Length == 0) {
            hr = 0;
        } else {
            object colObj = CreateComObject(CLSID_ObjectCollection, 3);
            if (colObj == null) { try { list.AbortList(); } catch { } return -2; }
            IObjectCollection collection = (IObjectCollection)colObj;
            for (int i = 0; i < links.Length; i++) {
                hr = collection.AddObject(links[i]);
                if (hr != 0) { try { list.AbortList(); } catch { } return hr; }
            }
            hr = list.AddUserTasks((IObjectArray)collection);
        }
        if (hr != 0) { try { list.AbortList(); } catch { } return hr; }
        if (!commit) { try { list.AbortList(); } catch { } return 0; }
        return list.CommitList();
    }

    private static string Hr(int hr) {
        if (hr == -1) { return "creation DestinationList impossible"; }
        if (hr == -2) { return "creation collection impossible"; }
        return "hr=0x" + hr.ToString("X8");
    }
}
'
$script:JumpListBroken=$false
try {
    Add-Type -TypeDefinition $sniperClipJumpCs
    if($null -eq ("SniperClipJumpList" -as [type])){
        $script:JumpListBroken=$true
        Write-SniperClipLog "Module Jump List non charge apres compilation." "WARN"
    } else {
        Write-SniperClipLog "Module Jump List charge [JL15]." "INFO"
        try {
            $okProc=[SniperClipJumpList]::SetProcessAppId($script:JumpListAppId)
            Write-SniperClipLog ("AppID du processus defini : "+$okProc) "INFO"
        } catch { Write-SniperClipLog ("AppID du processus impossible : " + $_.Exception.Message) "WARN" }
    }
} catch {
    $script:JumpListBroken=$true
    $detail=$_.Exception.Message
    try { if($null -ne $_.Exception.InnerException -and $_.Exception.InnerException.Message){ $detail=$detail+" | "+$_.Exception.InnerException.Message } } catch {}
    Write-SniperClipLog ("Compilation du module Jump List impossible : "+$detail) "WARN"
}

function Set-SniperClipWindowAppId {
    try {
        $ok=[SniperClipJumpList]::SetWindowAppId($form.Handle,$script:JumpListAppId)
        Write-SniperClipLog ("AppID de la fenetre defini : "+$ok) "INFO"
    } catch { Write-SniperClipLog ("AppID de la fenetre impossible : " + $_.Exception.Message) "WARN" }
}

function Get-JumpListCells {
    $ordered=@()
    foreach($i in @($script:CellOrder)){
        if(($i -ge 0) -and ($i -lt $count) -and ($ordered -notcontains [int]$i)){ $ordered+=[int]$i }
    }
    for($i=0;$i -lt $count;$i++){ if($ordered -notcontains $i){ $ordered+=$i } }
    $result=@()
    foreach($i in $ordered){
        if($result.Count -ge 10){ break }
        $slot=$slots[$i]
        if((-not [string]::IsNullOrEmpty($slot.Text)) -or (-not [string]::IsNullOrEmpty($slot.Rtf))){
            $label=$slot.Name
            if([string]::IsNullOrEmpty($label)){ $label=(T "Cellule ")+($i+1) }
            $result+=[pscustomobject]@{Index=$i;Label=$label}
        }
    }
    return ,@($result)
}

function Format-SniperClipHr {
    param([int]$hr)
    if($hr -eq 0){ return "0 (OK)" }
    if($hr -eq -100){ return "timeout du thread (-100)" }
    if($hr -eq -101){ return "thread impossible (-101)" }
    if($hr -eq -102){ return "creation du lien impossible (-102)" }
    return ("hr=0x{0:X8}" -f $hr)
}

$script:JumpListLauncher=""
$script:JumpListIcon=""
$script:JumpListLastOk=$null
$script:JumpListNeutral=$false
$script:JumpListProbed=$false
$script:JumpListVariant=0
$script:JumpListRefreshing=$false
$script:JumpListCopyWrapped=$false
$script:JumpListCopyActive=$false
$script:JumpListLnkDone=$false

function Refresh-SniperClipJumpList {
    if($script:JumpListRefreshing){ return }
    $script:JumpListRefreshing=$true
    try {
        if($script:JumpListBroken){ return }
        try { [void][SniperClipJumpList]::SetWindowAppId($form.Handle,$script:JumpListAppId) } catch {}
        if([string]::IsNullOrEmpty($script:JumpListLauncher)){
            if($script:IsCompiledBuild){
                try { $script:JumpListLauncher=(Get-Process -Id $PID).Path } catch { $script:JumpListLauncher="" }
                if([string]::IsNullOrEmpty($script:JumpListLauncher)){
                    try { $script:JumpListLauncher=[System.Reflection.Assembly]::GetEntryAssembly().Location } catch { $script:JumpListLauncher="" }
                }
                $script:JumpListIcon=$script:JumpListLauncher
            } else {
                $script:JumpListLauncher=Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
                $script:JumpListIcon=Join-Path $PSScriptRoot "SniperClip.ico"
                if(-not (Test-Path -LiteralPath $script:JumpListIcon)){ $script:JumpListIcon=$script:JumpListLauncher }
            }
            Write-SniperClipLog ("Jump List lanceur : "+$script:JumpListLauncher) "INFO"
        }
        if([string]::IsNullOrEmpty($script:JumpListLauncher)){ return }
        $cells=Get-JumpListCells
        $q=[char]34
        $taskPaths=@()
        $taskArgs=@()
        $taskNames=@()
        foreach($c in $cells){
            $taskPaths+=$script:JumpListLauncher
            if($script:IsCompiledBuild){
                $taskArgs+=("cell:"+$c.Index)
            } else {
                $taskArgs+=("-NoProfile -ExecutionPolicy Bypass -File "+$q+$PSCommandPath+$q+" -Task cell:"+$c.Index)
            }
            $taskNames+=((T "Copier")+" : "+$c.Label)
        }
        $res=[SniperClipJumpList]::UpdateJumpList($script:JumpListAppId,$taskPaths,$taskArgs,$taskNames,$script:JumpListIcon,$script:JumpListNeutral,$script:JumpListVariant)
        $ok=($res -eq "" -or $res -eq "aucune cellule")
        if($ok -ne $script:JumpListLastOk){
            $script:JumpListLastOk=$ok
            if($ok){
                $detail=""
                if($res -ne "" -and $res -ne "aucune cellule"){ $detail=" ["+$res+"]" }
                Write-SniperClipLog ("Jump List mise a jour : True ("+$cells.Count+" cellules)"+$detail) "INFO"
            } else {
                Write-SniperClipLog ("Jump List mise a jour : False ("+$res+")") "WARN"
            }
        }
        if(-not $ok -and -not $script:JumpListProbed){
            $script:JumpListProbed=$true
            $jlMax=10
            try {
                $jlReg=Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "JumpListItems_Maximum" -ErrorAction SilentlyContinue
                if($null -ne $jlReg){ $jlMax=[int]$jlReg.JumpListItems_Maximum }
            } catch {}
            $winName=""
            $winBuild=""
            try {
                $cv=Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
                if($null -ne $cv){
                    $winName=[string]$cv.ProductName
                    $winBuild=[string]$cv.CurrentBuildNumber
                    if($cv.DisplayVersion){ $winBuild=$winBuild+" ("+[string]$cv.DisplayVersion+")" }
                }
            } catch {}
            Write-SniperClipLog ("Diagnostics Jump List : Windows="+$winName+" build="+$winBuild+" osAPI="+[Environment]::OSVersion.Version.ToString()+" limiteElements="+$jlMax) "INFO"
            $notepadExe=Join-Path $env:WINDIR "System32\notepad.exe"
            $l1=[SniperClipJumpList]::ProbeTaskLite($null,$notepadExe,"","Sonde minimale","",0)
            Write-SniperClipLog ("Sonde minimale sans AppID (style pwsh) : "+(Format-SniperClipHr $l1)) "INFO"
            $l2=[SniperClipJumpList]::ProbeTaskLite($script:JumpListAppId,$notepadExe,"","Sonde minimale","",1)
            Write-SniperClipLog ("Sonde minimale avec AppID : "+(Format-SniperClipHr $l2)) "INFO"
            $l3=[SniperClipJumpList]::ProbeTaskLite($script:JumpListAppId,$notepadExe,"cell:0","Sonde minimale","",2)
            Write-SniperClipLog ("Sonde minimale avec arguments : "+(Format-SniperClipHr $l3)) "INFO"
            $l4=[SniperClipJumpList]::ProbeTaskLite($script:JumpListAppId,$notepadExe,"","Sonde minimale",$notepadExe,3)
            Write-SniperClipLog ("Sonde minimale avec icone : "+(Format-SniperClipHr $l4)) "INFO"
            $hrA=[SniperClipJumpList]::ProbeTask($script:JumpListAppId,$script:JumpListLauncher,"cell:0","Test SniperClip",$script:JumpListIcon,0)
            Write-SniperClipLog ("Sonde meme exe, titre neutre : "+(Format-SniperClipHr $hrA)) "INFO"
            $hrAppId=[SniperClipJumpList]::ProbeTask("SniperClip.Sonde",$script:JumpListLauncher,"cell:0","Test SniperClip",$script:JumpListIcon,0)
            Write-SniperClipLog ("Sonde AppID different : "+(Format-SniperClipHr $hrAppId)) "INFO"
            $hrNoIcon=[SniperClipJumpList]::ProbeTask($script:JumpListAppId,$script:JumpListLauncher,"cell:0","Test SniperClip","",0)
            Write-SniperClipLog ("Sonde sans icone : "+(Format-SniperClipHr $hrNoIcon)) "INFO"
            $shell32Icon=Join-Path ([Environment]::SystemDirectory) "shell32.dll"
            $hrSysIcon=[SniperClipJumpList]::ProbeTask($script:JumpListAppId,$script:JumpListLauncher,"cell:0","Test SniperClip",$shell32Icon,0)
            Write-SniperClipLog ("Sonde icone shell32 : "+(Format-SniperClipHr $hrSysIcon)) "INFO"
            $hrNoTitle=[SniperClipJumpList]::ProbeTask($script:JumpListAppId,$script:JumpListLauncher,"cell:0","Test SniperClip",$script:JumpListIcon,3)
            Write-SniperClipLog ("Sonde sans titre systeme : "+(Format-SniperClipHr $hrNoTitle)) "INFO"
            $hrB=[SniperClipJumpList]::ProbeTask($script:JumpListAppId,$notepadExe,"-Sonde","Sonde",$notepadExe,0)
            Write-SniperClipLog ("Sonde notepad, icone notepad : "+(Format-SniperClipHr $hrB)) "INFO"
            $hrK=[SniperClipJumpList]::ProbeRecent($script:JumpListAppId)
            Write-SniperClipLog ("Sonde categorie Recents : "+(Format-SniperClipHr $hrK)) "INFO"
            if($hrAppId -eq 0 -and $hrA -ne 0){
                Write-SniperClipLog "Sonde AppID different reussie : etat Windows de l AppID probablement corrompu (AutomaticDestinations)." "WARN"
            }
            if($script:JumpListVariant -eq 0){
                if($l3 -eq 0){ $script:JumpListVariant=5 }
                elseif($hrNoIcon -eq 0){ $script:JumpListVariant=1 }
                elseif($hrSysIcon -eq 0){ $script:JumpListVariant=2 }
                elseif($hrNoTitle -eq 0){ $script:JumpListVariant=3 }
            }
            if($hrA -eq 0){ $script:JumpListNeutral=$true }
            if($hrA -eq 0 -or $script:JumpListVariant -gt 0){
                $res2=[SniperClipJumpList]::UpdateJumpList($script:JumpListAppId,$taskPaths,$taskArgs,$taskNames,$script:JumpListIcon,$true,$script:JumpListVariant)
                $ok2=($res2 -eq "" -or $res2 -eq "aucune cellule")
                Write-SniperClipLog ("Jump List variante "+$script:JumpListVariant+" : "+$ok2+" ("+$res2+")") "INFO"
                if($ok2){ $ok=$true; $script:JumpListLastOk=$true }
                else { $script:JumpListBroken=$true }
            } else {
                if($l2 -eq 0 -and $l3 -ne 0){ Write-SniperClipLog "Lien minimal accepte mais arguments refuses : encodage des arguments a corriger." "WARN" }
                if($l1 -eq 0 -and $l2 -ne 0){ Write-SniperClipLog "Lien minimal accepte sans AppID seulement : AppID en cause avec les liens." "WARN" }
                $script:JumpListBroken=$true
            }
        }
    } catch {
        if(-not $script:JumpListBroken){
            $script:JumpListBroken=$true
            Write-SniperClipLog ("Actualisation de la Jump List impossible : " + $_.Exception.Message) "WARN"
        }
    } finally {
        $script:JumpListRefreshing=$false
    }
}

$script:jumpTaskTimer=New-Object System.Windows.Forms.Timer
$script:jumpTaskTimer.Interval=400
$script:jumpTaskTicks=0
$script:jumpTaskTimer.Add_Tick({
    if(-not $script:JumpListCopyWrapped){
        $script:JumpListCopyWrapped=$true
        try {
            $origCmd=Get-Command -Name Set-ClipboardFromSlot -ErrorAction SilentlyContinue
            if($null -ne $origCmd){
                $script:SniperClipOrigCopy=$origCmd.ScriptBlock
                function script:Set-ClipboardFromSlot {
                    $result = & $script:SniperClipOrigCopy @args
                    try {
                        if($args.Count -gt 0){
                            Update-CellOrder ([int]$args[0])
                            if(-not $script:JumpListBroken){ Refresh-SniperClipJumpList }
                        }
                    } catch {}
                    if($null -ne $result){ return $result }
                }
                $script:JumpListCopyActive=$true
                Write-SniperClipLog "Ordre Jump List suit aussi les copies faites dans la fenetre." "INFO"
            } else {
                Write-SniperClipLog "Fonction de copie introuvable : ordre limite aux taches Jump List." "WARN"
            }
        } catch { Write-SniperClipLog ("Enveloppe de copie impossible : " + $_.Exception.Message) "WARN" }
    }
    if(-not $script:JumpListLnkDone){
        $script:JumpListLnkDone=$true
        try {
            $lnkPath=$script:StartupShortcut
            if([string]::IsNullOrEmpty($lnkPath)){ $lnkPath=Join-Path ([Environment]::GetFolderPath("Startup")) "SniperClip.lnk" }
            if(-not [string]::IsNullOrEmpty($lnkPath) -and (Test-Path -LiteralPath $lnkPath)){
                $okLnk=[SniperClipJumpList]::SetLnkAppId($lnkPath,$script:JumpListAppId)
                Write-SniperClipLog ("AppID du raccourci Demarrage defini : "+$okLnk+" ("+$lnkPath+")") "INFO"
            } else {
                Write-SniperClipLog "Raccourci Demarrage introuvable : AppID raccourci non pose." "WARN"
            }
        } catch { Write-SniperClipLog ("AppID du raccourci Demarrage impossible : " + $_.Exception.Message) "WARN" }
    }
    try {
        $pending=Join-Path $DataDir "task.pending"
        if(Test-Path -LiteralPath $pending){
            $task=([string](Get-Content -LiteralPath $pending -Raw)).Trim()
            Remove-Item -LiteralPath $pending -Force -ErrorAction SilentlyContinue
            if($task -match '^cell:(\d+)$'){
                $idx=[int]$Matches[1]
                if(($idx -ge 0) -and ($idx -lt $count)){
                    Set-ClipboardFromSlot $idx
                    if(-not $script:JumpListCopyActive){
                        Update-CellOrder $idx
                        if(-not $script:JumpListBroken){ Refresh-SniperClipJumpList }
                    }
                }
            } else {
                Write-SniperClipLog ("Tache Jump List inconnue : " + $task) "WARN"
            }
        }
    } catch { Write-SniperClipLog ("Traitement de la tache Jump List impossible : " + $_.Exception.Message) "WARN" }
    $script:jumpTaskTicks++
    if(($script:jumpTaskTicks % 12) -eq 0 -and -not $script:JumpListBroken){ Refresh-SniperClipJumpList }
})
$script:jumpTaskTimer.Start()

# Premier lancement direct depuis la Jump List (aucune autre instance en cours).
try {
    if(-not [string]::IsNullOrEmpty($Task) -and $Task -match '^cell:(\d+)$'){
        $idx=[int]$Matches[1]
        if(($idx -ge 0) -and ($idx -lt $count)){
            Set-ClipboardFromSlot $idx
            Update-CellOrder $idx
            if(-not $script:JumpListBroken){ Refresh-SniperClipJumpList }
        }
    }
} catch {}

try {
    $form.Add_HandleCreated({ try { [void][SniperClipJumpList]::SetWindowAppId($form.Handle,$script:JumpListAppId) } catch {} })
} catch {}
try { Set-SniperClipWindowAppId } catch {}
# Raccourcis clavier globaux
'@
    },
    @{
        Name = "P11 - Edition de cellule : ordre Jump List"
        Mandatory = $false
        Old = @'
        $slots[$cellIndex]=$newSlot
        Update-Button $cellIndex
        Save-Slots
'@
        New = @'
        $slots[$cellIndex]=$newSlot
        Update-CellOrder $cellIndex
        Update-Button $cellIndex
        Save-Slots
        Refresh-SniperClipJumpList
'@
    },
    @{
        Name = "P12 - Effacement de cellule : mise a jour Jump List"
        Mandatory = $false
        Old = @'
            $slots[$idx]=[pscustomobject]@{Name="";Text="";Rtf="";Html="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
            Update-Button $idx
            Save-Slots
'@
        New = @'
            $slots[$idx]=[pscustomobject]@{Name="";Text="";Rtf="";Html="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
            Update-Button $idx
            Save-Slots
            Refresh-SniperClipJumpList
'@
    },
    @{
        Name = "P13 - Logo sous le titre de la fenetre"
        Mandatory = $false
        Old = @'
$title = New-Object System.Windows.Forms.Label
$title.Text = "SniperClip"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold",16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(15,10)
'@
        New = @'
$title = New-Object System.Windows.Forms.Label
$title.Text = "SniperClip"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold",16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(15,10)

# Logo de l application affiche juste sous le nom, dans l en-tete.
# Source : PNG haute qualite integre au build (base64), sinon le fichier PNG
# a cote de l exe, sinon l icone de l exe. Taille x2.5 (50 px max), rendu net.
function script:Update-AppHeaderLogo {
    try {
        if($null -eq $script:appLogoBox){ return }
        if($null -eq $script:appLogoSource){ return }
        if($header.Height -le 70){
            # En-tete replie : le logo se place a droite du nom du logiciel,
            # il garde sa taille et reste bien visible.
            $h = [Math]::Max(30, [Math]::Min(50, $header.Height - 10))
            $w = [int]($h * $script:appLogoSource.Width / $script:appLogoSource.Height)
            if($w -lt 8){ $w = 8 }
            $logoX = 15
            try { $logoX = [int]$title.Location.X + [int]$title.Width + 12 } catch { }
            $logoMaxX = [int]($header.Width - $w - 5)
            if($logoX -gt $logoMaxX){ $logoX = $logoMaxX }
            if($logoX -lt 15){ $logoX = 15 }
            $logoY = [int](($header.Height - $h) / 2)
            if($logoY -lt 2){ $logoY = 2 }
            $script:appLogoBox.Location = New-Object System.Drawing.Point($logoX,$logoY)
        }else{
            # En-tete complet : le logo reste juste sous le nom du logiciel.
            $h = [Math]::Max(20, [Math]::Min(50, $header.Height - 42))
            $w = [int]($h * $script:appLogoSource.Width / $script:appLogoSource.Height)
            if($w -lt 8){ $w = 8 }
            $script:appLogoBox.Location = New-Object System.Drawing.Point(15,40)
        }
        $script:appLogoBox.Size = New-Object System.Drawing.Size($w, $h)
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($script:appLogoSource, 0, 0, $w, $h)
        $g.Dispose()
        $oldImg = $script:appLogoBox.Image
        $script:appLogoBox.Image = $bmp
        if($null -ne $oldImg){ $oldImg.Dispose() }
    } catch { }
}
try {
    $script:appLogoSource = $null
    $script:appLogoStream = $null
    if(-not [string]::IsNullOrEmpty($script:LogoB64)){
        try {
            $lb = [Convert]::FromBase64String($script:LogoB64)
            $script:appLogoStream = New-Object System.IO.MemoryStream(,$lb)
            $script:appLogoSource = [System.Drawing.Image]::FromStream($script:appLogoStream)
        } catch { $script:appLogoSource = $null }
    }
    if($null -eq $script:appLogoSource){
        $lp = Join-Path $script:AppDir "SniperClip_logo.png"
        if(Test-Path -LiteralPath $lp){
            $script:appLogoSource = [System.Drawing.Image]::FromFile($lp)
        } elseif($null -ne $script:appIcon){
            $script:appLogoSource = $script:appIcon.ToBitmap()
        }
    }
    if($null -ne $script:appLogoSource){
        $script:appLogoBox = New-Object System.Windows.Forms.PictureBox
        $script:appLogoBox.Location = New-Object System.Drawing.Point(15,40)
        $script:appLogoBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        [void]$header.Controls.Add($script:appLogoBox)
        $script:appLogoBox.Add_MouseDown({
            if($_.Button -eq [System.Windows.Forms.MouseButtons]::Right){ & $script:ShowHeaderMenu $this $_.Location }
        })
        $header.Add_Resize({ try { Update-AppHeaderLogo } catch { } })
        Update-AppHeaderLogo
    }
} catch { $script:appLogoBox = $null }
'@
    },

    @{
        Name = "P14a - Grille : dimensions persistees a l ouverture"
        Mandatory = $true
        Old = @'
$columns = 5
$rows = 6
$count = $columns * $rows

$slots=New-Object object[] $count
for($i=0;$i -lt $count;$i++){
    $slots[$i]=[pscustomobject]@{Name="";Text="";Rtf="";Html="";CellBack="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
}
'@
        New = @'
$columns = 5
$rows = 6
$script:MaxGridColumns = 30
$script:MaxGridRows = 30
$script:hiddenSlots = @{}
$script:headerCollapsed = $false

# P14a : dimensions persistees de la grille, lues avant le chargement des
# cellules. Premiere ouverture : 5 colonnes x 6 lignes. Limite : 30 x 30.
# L etat masque de l en-tete est persiste dans le meme reglage Grid.
try {
    $earlyGrid = $null
    try {
        $earlyGridRaw = Db-GetSetting "Grid"
        if(-not [string]::IsNullOrEmpty($earlyGridRaw)){
            $earlyGrid = (UnB64 $earlyGridRaw) | ConvertFrom-Json
        }
    } catch { $earlyGrid = $null }
    if($null -ne $earlyGrid){
        if($null -ne $earlyGrid.Columns){ $columns = [int][math]::Max(1,[int][math]::Min($script:MaxGridColumns,[int]$earlyGrid.Columns)) }
        if($null -ne $earlyGrid.Rows){ $rows = [int][math]::Max(1,[int][math]::Min($script:MaxGridRows,[int]$earlyGrid.Rows)) }
        if($null -ne $earlyGrid.HeaderCollapsed){ $script:headerCollapsed = [bool]$earlyGrid.HeaderCollapsed }
    }
} catch { }
# Marqueur de format. GridV3 : l index SQLite est le numero d ordre de la
# cellule (stockage lineaire), identique quelles que soient les dimensions.
# GridV2 : index = ligne*30+colonne (converti au chargement). Sans marqueur :
# ancien format (index d affichage de la grille a 5 colonnes).
$script:GridStorageV3 = $false
$script:GridStorageV2 = $false
try {
    $gridV3Raw = Db-GetSetting "GridV3"
    if(-not [string]::IsNullOrEmpty($gridV3Raw)){ $script:GridStorageV3 = $true }
} catch { }
if(-not $script:GridStorageV3){
    try {
        $gridV2Raw = Db-GetSetting "GridV2"
        if(-not [string]::IsNullOrEmpty($gridV2Raw)){ $script:GridStorageV2 = $true }
    } catch { }
}

$count = $columns * $rows

$slots=New-Object object[] $count
for($i=0;$i -lt $count;$i++){
    $slots[$i]=[pscustomobject]@{Name="";Text="";Rtf="";Html="";CellBack="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
}
'@
    },
    @{
        Name = "P14b - Grille : chargement SQLite des cellules"
        Mandatory = $true
        Old = @'
    if($hasCells -and -not $useLegacyMigration){
        foreach($item in $existingRows){
            $idx=[int]$item.Index
            if($idx -ge 0 -and $idx -lt $count){
                $slots[$idx]=[pscustomobject]@{
                    Name=UnB64 $item.NameB64; Text=UnB64 $item.TextB64; Rtf=UnB64 $item.RtfB64; Html=UnB64 $item.HtmlB64
                    CellBack=[string]$item.CellBack; Shortcut=[string]$item.Shortcut; ShortcutModifiers=[int]$item.ShortcutModifiers; ShortcutKey=[int]$item.ShortcutKey
                }
            }
        }
    }else{
'@
        New = @'
    if($hasCells -and -not $useLegacyMigration){
        foreach($item in $existingRows){
            $idx=[int]$item.Index
            if($idx -ge 0){
                $linear=$idx
                if((-not $script:GridStorageV3) -and $script:GridStorageV2){
                    $gr=[int][math]::Floor($idx/30); $gc=$idx % 30
                    $linear=($gr*$columns)+$gc
                }
                $loadedSlot=[pscustomobject]@{
                    Name=UnB64 $item.NameB64; Text=UnB64 $item.TextB64; Rtf=UnB64 $item.RtfB64; Html=UnB64 $item.HtmlB64
                    CellBack=[string]$item.CellBack; Shortcut=[string]$item.Shortcut; ShortcutModifiers=[int]$item.ShortcutModifiers; ShortcutKey=[int]$item.ShortcutKey
                }
                if($linear -lt $count){
                    $slots[$linear]=$loadedSlot
                }else{
                    $script:hiddenSlots[([string]$linear)]=$loadedSlot
                }
            }
        }
    }else{
'@
    },
    @{
        Name = "P14c - Grille : migration JSON heritee"
        Mandatory = $true
        Old = @'
            if($null -ne $sourceCells){
                foreach($item in $sourceCells){
                    $idx=[int]$item.Index
                    if($idx -ge 0 -and $idx -lt $count){
                        $slots[$idx]=[pscustomobject]@{
                            Name=[string]$item.Name; Text=[string]$item.Text; Rtf=[string]$item.Rtf; Html=[string]$item.Html
                            CellBack=[string]$item.CellBack; Shortcut=[string]$item.Shortcut; ShortcutModifiers=[int]$item.ShortcutModifiers; ShortcutKey=[int]$item.ShortcutKey
                        }
                    }
                }
            }
'@
        New = @'
            if($null -ne $sourceCells){
                foreach($item in $sourceCells){
                    $idx=[int]$item.Index
                    if($idx -ge 0){
                        $linear=$idx
                        $loadedSlot=[pscustomobject]@{
                            Name=[string]$item.Name; Text=[string]$item.Text; Rtf=[string]$item.Rtf; Html=[string]$item.Html
                            CellBack=[string]$item.CellBack; Shortcut=[string]$item.Shortcut; ShortcutModifiers=[int]$item.ShortcutModifiers; ShortcutKey=[int]$item.ShortcutKey
                        }
                        if($linear -lt $count){
                            $slots[$linear]=$loadedSlot
                        }else{
                            $script:hiddenSlots[([string]$linear)]=$loadedSlot
                        }
                    }
                }
            }
'@
    },
    @{
        Name = "P14d - Grille : sauvegarde des cellules affichees et masquees"
        Mandatory = $true
        Old = @'
            $currentSql = "DELETE FROM cells;"
            Db-Exec $currentSql
            for($i=0;$i -lt $count;$i++){
                $slot=$slots[$i]
                $currentSql="INSERT INTO cells(idx,name_b64,text_b64,rtf_b64,html_b64,cellback,shortcut,shortcut_mod,shortcut_key) VALUES("+
                    $i+","+(Db-Quote (B64 ([string]$slot.Name)))+","+(Db-Quote (B64 ([string]$slot.Text)))+","+(Db-Quote (B64 ([string]$slot.Rtf)))+","+(Db-Quote (B64 ([string]$slot.Html)))+","+(Db-Quote ([string]$slot.CellBack))+","+(Db-Quote ([string]$slot.Shortcut))+","+[int]$slot.ShortcutModifiers+","+[int]$slot.ShortcutKey+");"
                Db-Exec $currentSql
            }
'@
        New = @'
            $currentSql = "DELETE FROM cells;"
            Db-Exec $currentSql
            for($i=0;$i -lt $count;$i++){
                $slot=$slots[$i]
                $storageIdx=$i
                $currentSql="INSERT INTO cells(idx,name_b64,text_b64,rtf_b64,html_b64,cellback,shortcut,shortcut_mod,shortcut_key) VALUES("+
                    $storageIdx+","+(Db-Quote (B64 ([string]$slot.Name)))+","+(Db-Quote (B64 ([string]$slot.Text)))+","+(Db-Quote (B64 ([string]$slot.Rtf)))+","+(Db-Quote (B64 ([string]$slot.Html)))+","+(Db-Quote ([string]$slot.CellBack))+","+(Db-Quote ([string]$slot.Shortcut))+","+[int]$slot.ShortcutModifiers+","+[int]$slot.ShortcutKey+");"
                Db-Exec $currentSql
            }
            foreach($hiddenKey in @($script:hiddenSlots.Keys)){
                $hiddenSlot=$script:hiddenSlots[$hiddenKey]
                if($null -eq $hiddenSlot){ continue }
                $storageIdx=[int]$hiddenKey
                $currentSql="INSERT INTO cells(idx,name_b64,text_b64,rtf_b64,html_b64,cellback,shortcut,shortcut_mod,shortcut_key) VALUES("+
                    $storageIdx+","+(Db-Quote (B64 ([string]$hiddenSlot.Name)))+","+(Db-Quote (B64 ([string]$hiddenSlot.Text)))+","+(Db-Quote (B64 ([string]$hiddenSlot.Rtf)))+","+(Db-Quote (B64 ([string]$hiddenSlot.Html)))+","+(Db-Quote ([string]$hiddenSlot.CellBack))+","+(Db-Quote ([string]$hiddenSlot.Shortcut))+","+[int]$hiddenSlot.ShortcutModifiers+","+[int]$hiddenSlot.ShortcutKey+");"
                Db-Exec $currentSql
            }
'@
    },
    @{
        Name = "P14e - Grille : etat de l en-tete persiste"
        Mandatory = $true
        Old = @'
                $gridConfig=[pscustomobject]@{Columns=[int]$columns;Rows=[int]$rows;HeaderHeight=[int]$headerHeight;ColumnWeights=@($columnWeights | ForEach-Object {[double]$_});RowWeights=@($rowWeights | ForEach-Object {[double]$_})}
'@
        New = @'
                $gridConfig=[pscustomobject]@{Columns=[int]$columns;Rows=[int]$rows;HeaderHeight=[int]$headerHeight;HeaderCollapsed=[bool]$script:headerCollapsed;ColumnWeights=@($columnWeights | ForEach-Object {[double]$_});RowWeights=@($rowWeights | ForEach-Object {[double]$_})}
'@
    },
    @{
        Name = "P14f - Grille : marqueur de format GridV2"
        Mandatory = $true
        Old = @'
                foreach($pair in @(@("Window",($window|ConvertTo-Json -Compress -Depth 6)),@("Grid",($gridConfig|ConvertTo-Json -Compress -Depth 6)),@("Theme",($theme|ConvertTo-Json -Compress -Depth 6)),@("Language",$script:Language))){
'@
        New = @'
                foreach($pair in @(@("Window",($window|ConvertTo-Json -Compress -Depth 6)),@("Grid",($gridConfig|ConvertTo-Json -Compress -Depth 6)),@("GridV2","1"),@("GridV3","1"),@("Theme",($theme|ConvertTo-Json -Compress -Depth 6)),@("Language",$script:Language))){
'@
    },
    @{
        Name = "P14g - Grille : proportions dynamiques"
        Mandatory = $true
        Old = @'
$columnWeights = @(1.0,1.0,1.0,1.0,1.0)
$rowWeights = @(1.0,1.0,1.0,1.0,1.0,1.0)
'@
        New = @'
# P14g : proportions dimensionnees sur le nombre reel de colonnes et de lignes.
$columnWeights = @(1.0) * $columns
$rowWeights = @(1.0) * $rows
'@
    },
    @{
        Name = "P14h - Grille : creation des boutons en fonction"
        Mandatory = $true
        Old = @'
$buttons = @()
for ($i=0; $i -lt $count; $i++) {
    $b = New-Object System.Windows.Forms.Button
'@
        New = @'
$buttons = @()
function New-GridButton([int]$i) {
    $b = New-Object System.Windows.Forms.Button
'@
    },
    @{
        Name = "P14i - Grille : reconstruction des boutons et choix des dimensions"
        Mandatory = $true
        Old = @'
    $buttons += $b
    $grid.Controls.Add($b)
}

for ($i=0; $i -lt $count; $i++) { Update-Button $i }

Apply-Layout
'@
        New = @'
    return $b
}

function Rebuild-GridButtons {
    foreach($oldButton in @($script:buttons)){
        try{ $grid.Controls.Remove($oldButton) }catch{}
        try{ $oldButton.Dispose() }catch{}
    }
    $script:buttons=@()
    for($i=0;$i -lt $count;$i++){
        $newButton=New-GridButton $i
        $script:buttons += $newButton
        $grid.Controls.Add($newButton)
    }
    for($i=0;$i -lt $count;$i++){ Update-Button $i }
}

function Test-SlotHasData($slot){
    if($null -eq $slot){ return $false }
    if(-not [string]::IsNullOrEmpty([string]$slot.Name)){ return $true }
    if(-not [string]::IsNullOrEmpty([string]$slot.Text)){ return $true }
    if(-not [string]::IsNullOrEmpty([string]$slot.Rtf)){ return $true }
    if(-not [string]::IsNullOrEmpty([string]$slot.Html)){ return $true }
    if(-not [string]::IsNullOrEmpty([string]$slot.CellBack)){ return $true }
    if(-not [string]::IsNullOrEmpty([string]$slot.Shortcut)){ return $true }
    if([int]$slot.ShortcutModifiers -ne 0){ return $true }
    if([int]$slot.ShortcutKey -ne 0){ return $true }
    return $false
}

function Get-GridHiddenDataCount([int]$newCols,[int]$newRows){
    $newTotal=$newCols*$newRows
    $hiddenCount=0
    for($i=$newTotal;$i -lt $count;$i++){
        if(Test-SlotHasData $script:slots[$i]){ $hiddenCount++ }
    }
    return $hiddenCount
}

function Set-GridDimensions([int]$newCols,[int]$newRows){
    if($newCols -lt 1){ $newCols=1 }
    if($newCols -gt $script:MaxGridColumns){ $newCols=$script:MaxGridColumns }
    if($newRows -lt 1){ $newRows=1 }
    if($newRows -gt $script:MaxGridRows){ $newRows=$script:MaxGridRows }
    if(($newCols -eq $columns) -and ($newRows -eq $rows)){ return }

    Hide-Preview
    $newCount=$newCols*$newRows

    # Stockage lineaire : chaque cellule garde son numero d ordre. Celles qui
    # ne tiennent plus dans la nouvelle grille passent dans la reserve
    # masquee ; la reserve reprend ses cellules des que la grille redevient
    # assez grande. A nombre total de cellules egal, rien ne bouge.
    $newHidden=@{}
    foreach($keptKey in @($script:hiddenSlots.Keys)){
        $newHidden[$keptKey]=$script:hiddenSlots[$keptKey]
    }
    for($i=$newCount;$i -lt $count;$i++){
        $movedSlot=$script:slots[$i]
        if(Test-SlotHasData $movedSlot){ $newHidden[([string]$i)]=$movedSlot }
    }
    $newSlots=New-Object object[] $newCount
    for($i=0;$i -lt $newCount;$i++){
        $posKey=[string]$i
        if($newHidden.ContainsKey($posKey)){
            $newSlots[$i]=$newHidden[$posKey]
            $newHidden.Remove($posKey)
        }elseif($i -lt $count){
            $newSlots[$i]=$script:slots[$i]
        }else{
            $newSlots[$i]=[pscustomobject]@{Name="";Text="";Rtf="";Html="";CellBack="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
        }
    }

    $script:slots=$newSlots
    $script:hiddenSlots=$newHidden
    $script:columns=$newCols
    $script:rows=$newRows
    $script:count=$newCount

    $newColumnWeights=@()
    for($c=0;$c -lt $newCols;$c++){
        if($c -lt $script:columnWeights.Count){ $newColumnWeights += [double]$script:columnWeights[$c] }
        else{ $newColumnWeights += 1.0 }
    }
    $script:columnWeights=$newColumnWeights
    $newRowWeights=@()
    for($r=0;$r -lt $newRows;$r++){
        if($r -lt $script:rowWeights.Count){ $newRowWeights += [double]$script:rowWeights[$r] }
        else{ $newRowWeights += 1.0 }
    }
    $script:rowWeights=$newRowWeights

    Rebuild-GridButtons
    Apply-Layout
    Update-HeaderLayout
    try { Save-Slots } catch {}

    try { $script:CellOrder=@() } catch {}
    try {
        if(Get-Command Refresh-SniperClipJumpList -ErrorAction SilentlyContinue){
            Refresh-SniperClipJumpList
        }
    } catch {}

    Write-SniperClipLog ("Grille reconfiguree : "+$newCols+" colonnes x "+$newRows+" lignes ("+$newCount+" cellules).")
}

function Edit-GridDimensions {
    Hide-Preview
    $dlg=New-Object System.Windows.Forms.Form
    $dlg.Text=(T-Grid "Nombre de cellules")
    $dlg.StartPosition="CenterParent"
    $dlg.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MinimizeBox=$false
    $dlg.MaximizeBox=$false
    $dlg.ShowInTaskbar=$false
    $dlg.ClientSize=New-Object System.Drawing.Size(380,230)

    $info=New-Object System.Windows.Forms.Label
    $info.Text=(T-Grid "Colonnes et lignes de la grille (maximum 30 x 30).")
    $info.Location=New-Object System.Drawing.Point(15,15)
    $info.AutoSize=$true

    $colLabel=New-Object System.Windows.Forms.Label
    $colLabel.Text=(T-Grid "Colonnes :")
    $colLabel.Location=New-Object System.Drawing.Point(15,55)
    $colLabel.AutoSize=$true

    $colNum=New-Object System.Windows.Forms.NumericUpDown
    $colNum.Minimum=1
    $colNum.Maximum=$script:MaxGridColumns
    $colNum.Value=[decimal]$columns
    $colNum.Location=New-Object System.Drawing.Point(110,52)
    $colNum.Size=New-Object System.Drawing.Size(70,25)

    $rowLabel=New-Object System.Windows.Forms.Label
    $rowLabel.Text=(T-Grid "Lignes :")
    $rowLabel.Location=New-Object System.Drawing.Point(15,95)
    $rowLabel.AutoSize=$true

    $rowNum=New-Object System.Windows.Forms.NumericUpDown
    $rowNum.Minimum=1
    $rowNum.Maximum=$script:MaxGridRows
    $rowNum.Value=[decimal]$rows
    $rowNum.Location=New-Object System.Drawing.Point(110,92)
    $rowNum.Size=New-Object System.Drawing.Size(70,25)

    $totalLabel=New-Object System.Windows.Forms.Label
    $totalLabel.Text=""
    $totalLabel.Location=New-Object System.Drawing.Point(15,135)
    $totalLabel.AutoSize=$true

    $updateTotal={
        try{
            $totalValue=([int]$colNum.Value)*([int]$rowNum.Value)
            $totalLabel.Text=(T-Grid "Total : ")+$totalValue+(T-Grid " cellules")
        }catch{}
    }
    $colNum.Add_ValueChanged($updateTotal)
    $rowNum.Add_ValueChanged($updateTotal)
    & $updateTotal

    $ok=New-Object System.Windows.Forms.Button
    $ok.Text=(T-Grid "Appliquer")
    $ok.DialogResult=[System.Windows.Forms.DialogResult]::OK
    $ok.Location=New-Object System.Drawing.Point(180,185)
    $ok.Size=New-Object System.Drawing.Size(85,32)

    $cancel=New-Object System.Windows.Forms.Button
    $cancel.Text=(T-Grid "Annuler")
    $cancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location=New-Object System.Drawing.Point(275,185)
    $cancel.Size=New-Object System.Drawing.Size(85,32)

    $dlg.Controls.AddRange(@($info,$colLabel,$colNum,$rowLabel,$rowNum,$totalLabel,$ok,$cancel))
    $dlg.AcceptButton=$ok
    $dlg.CancelButton=$cancel

    $result=$dlg.ShowDialog($form)
    $newCols=[int]$colNum.Value
    $newRows=[int]$rowNum.Value
    $dlg.Dispose()
    if($result -ne [System.Windows.Forms.DialogResult]::OK){ return }
    if(($newCols -eq $columns) -and ($newRows -eq $rows)){ return }

    $hiddenCount=Get-GridHiddenDataCount $newCols $newRows
    if($hiddenCount -gt 0){
        $confirmMsg=([string]$hiddenCount+(T-Grid " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?"))
        $answer=Show-LocalizedConfirm $form $confirmMsg
        if($answer -ne [System.Windows.Forms.DialogResult]::Yes){ return }
    }
    Set-GridDimensions $newCols $newRows
}

Rebuild-GridButtons

Apply-Layout
'@
    },
    @{
        Name = "P15a - Nombre de cellules : bouton de l en-tete"
        Mandatory = $true
        Old = @'
$sizeButton = New-Object System.Windows.Forms.Button
$sizeButton.Text = (T "Taille des cellules")
$sizeButton.Font = New-Object System.Drawing.Font("Segoe UI",9)
$sizeButton.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 135),15)
$sizeButton.Size = New-Object System.Drawing.Size(120,32)
$sizeButton.Anchor = "Top, Right"
$sizeButton.FlatStyle = "Flat"
$sizeButton.Add_Click({ Edit-GridSize })
'@
        New = @'
# Traductions des libelles ajoutes par la grille parametrable. Le logiciel
# traduit d abord via sa propre table (T) ; si la cle est absente, une table
# de repli fournit le polonais ou l anglais selon la langue de l interface.
function script:T-Grid([string]$gridKey){
    $gridValue=$gridKey
    try { $gridValue=[string](T $gridKey) } catch { $gridValue=$gridKey }
    if([string]::IsNullOrEmpty($gridValue)){ $gridValue=$gridKey }
    if($gridValue -cne $gridKey){ return $gridValue }
    $gridFr=$true
    try {
        $gridFr=(([string](T "Tailles par défaut")) -ceq "Tailles par défaut")
    } catch { $gridFr=$true }
    if(-not $gridFr){
        try { $gridFr=(([string](T "Quitter SniperClip")) -ceq "Quitter SniperClip") } catch { }
    }
    if($gridFr){ return $gridKey }
    $gridPl=$false
    try { $gridPl=(([string]$script:Language) -match "^pl|pol") } catch { $gridPl=$false }
    if(-not $gridPl){
        try { $gridPl=(([string](T "Tailles par défaut")) -eq "Rozmiary domyślne") } catch { }
    }
    if($gridPl){
        switch($gridKey){
            "Nombre de cellules" { return "Liczba komórek" }
            "Colonnes et lignes de la grille (maximum 30 x 30)." { return "Kolumny i wiersze siatki (maksymalnie 30 x 30)." }
            "Colonnes :" { return "Kolumny:" }
            "Lignes :" { return "Wiersze:" }
            "Total : " { return "Łącznie: " }
            " cellules" { return " komórek" }
            "Appliquer" { return "Zastosuj" }
            "Annuler" { return "Anuluj" }
            "Personnaliser" { return "Personalizuj" }
            "Tailles par défaut" { return "Rozmiary domyślne" }
            "En-tête : masquer" { return "Nagłówek: ukryj" }
            "En-tête : afficher" { return "Nagłówek: pokaż" }
            " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?" { return " komórek zawierających dane nie będzie już wyświetlanych. Są zachowywane i pojawią się ponownie po powiększeniu siatki. Kontynuować?" }
            default { return $gridKey }
        }
    }
    switch($gridKey){
        "Nombre de cellules" { return "Cell count" }
        "Colonnes et lignes de la grille (maximum 30 x 30)." { return "Grid columns and rows (maximum 30 x 30)." }
        "Colonnes :" { return "Columns:" }
        "Lignes :" { return "Rows:" }
        "Total : " { return "Total: " }
        " cellules" { return " cells" }
        "Appliquer" { return "Apply" }
        "Annuler" { return "Cancel" }
        "Personnaliser" { return "Customize" }
        "Tailles par défaut" { return "Default sizes" }
        "En-tête : masquer" { return "Header: hide" }
        "En-tête : afficher" { return "Header: show" }
        " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?" { return " cells containing data will no longer be displayed. They are kept and will reappear if you enlarge the grid. Continue ?" }
        default { return $gridKey }
    }
}

$sizeButton = New-Object System.Windows.Forms.Button
$sizeButton.Text = (T-Grid "Nombre de cellules")
$sizeButton.Font = New-Object System.Drawing.Font("Segoe UI",9)
$sizeButton.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 135),15)
$sizeButton.Size = New-Object System.Drawing.Size(120,32)
$sizeButton.Anchor = "Top, Right"
$sizeButton.FlatStyle = "Flat"
$sizeButton.Add_Click({ Edit-GridDimensions })
'@
    },
    @{
        Name = "P15b - Tailles par defaut : grille dynamique"
        Mandatory = $true
        Old = @'
function Reset-GridSizes {
    $columnWeights=@(1.0,1.0,1.0,1.0,1.0)
    $rowWeights=@(1.0,1.0,1.0,1.0,1.0,1.0)
    $script:manualLayout=$false
    $script:manualColumnWidths=@(0,0,0,0,0)
    $script:manualRowHeights=@(0,0,0,0,0,0)
    Apply-Layout
    Save-Slots
}
'@
        New = @'
function Reset-GridSizes {
    $script:columnWeights=@(1.0) * $columns
    $script:rowWeights=@(1.0) * $rows
    $script:manualLayout=$false
    $script:manualColumnWidths=@(0) * $columns
    $script:manualRowHeights=@(0) * $rows
    Apply-Layout
    Update-AllButtons
    Save-Slots
}
'@
    },
    @{
        Name = "P15c - Taille des cellules : defilement du dialogue"
        Mandatory = $true
        Old = @'
    $dlg.Text = (T "SniperClip - taille des cellules")
    $dlg.StartPosition = "CenterParent"
    $dlg.Size = New-Object System.Drawing.Size(520,430)
'@
        New = @'
    $dlg.Text = (T "SniperClip - taille des cellules")
    $dlg.StartPosition = "CenterParent"
    $dlg.Size = New-Object System.Drawing.Size(520,430)
    $dlg.AutoScroll = $true
'@
    },
    @{
        Name = "P16a - En-tete : libelle du bouton Nombre de cellules"
        Mandatory = $true
        Old = @'
    $sizeW=Localized-ButtonWidth (T "Taille des cellules") 120 24
'@
        New = @'
    $sizeW=Localized-ButtonWidth (T-Grid "Nombre de cellules") 120 24
'@
    },
    @{
        Name = "P16b - En-tete : masquage automatique si fenetre etroite"
        Mandatory = $true
        Old = @'
    $oneLineAvailable=[math]::Max(0,$w-125-10)

    $oneLine=($w -ge 900 -and $totalW -le $oneLineAvailable)
'@
        New = @'
    $oneLineAvailable=[math]::Max(0,$w-125-10)

    # P16b : en-tete masque par l utilisateur, ou rangee de boutons trop
    # large pour la fenetre. La marge gauche de 75 px reserve la place du
    # logo (50 px max sous le titre) : la rangee ne passe jamais dessous.
    # Tout replie, seul le nom du logiciel et le logo restent affiches. Les
    # fonctions restent accessibles par le clic droit dans l en-tete et par
    # le menu du systray.
    $autoHide=($script:headerCollapsed -or (($w-85) -lt ($totalW+10)))
    $oneLine=(-not $autoHide)
'@
    },
    @{
        Name = "P16c - En-tete : mode complet (aide puis boutons sur 2e ligne)"
        Mandatory = $true
        Old = @'
    if($oneLine){
        $headerHeight=62
        $header.Size=New-Object System.Drawing.Size($w,$headerHeight)
        $title.Location=New-Object System.Drawing.Point(15,10)
        $customButton.Size=New-Object System.Drawing.Size($customW,32)
        $resetSizeButton.Size=New-Object System.Drawing.Size($resetW,32)
        $sizeButton.Size=New-Object System.Drawing.Size($sizeW,32)
        $sizeX=$w-$sizeW-5
        $resetX=$sizeX-$resetW-$gap
        $customX=$resetX-$customW-$gap
        $customButton.Location=New-Object System.Drawing.Point($customX,15)
        $resetSizeButton.Location=New-Object System.Drawing.Point($resetX,15)
        $sizeButton.Location=New-Object System.Drawing.Point($sizeX,15)
        $help.AutoSize=$false
        $help.AutoEllipsis=$false
        $help.Font=New-Object System.Drawing.Font("Segoe UI",9)
        $help.Location=New-Object System.Drawing.Point(125,16)
        $help.Size=New-Object System.Drawing.Size([math]::Max(120,$customX-135),30)
    }else{
'@
        New = @'
    if($oneLine){
        $headerHeight=105
        $header.Size=New-Object System.Drawing.Size($w,$headerHeight)
        $title.Location=New-Object System.Drawing.Point(15,10)
        $help.Visible=$true
        $customButton.Visible=$true
        $resetSizeButton.Visible=$true
        $sizeButton.Visible=$true
        $customButton.Size=New-Object System.Drawing.Size($customW,32)
        $resetSizeButton.Size=New-Object System.Drawing.Size($resetW,32)
        $sizeButton.Size=New-Object System.Drawing.Size($sizeW,32)
        $sizeX=$w-$sizeW-5
        $resetX=$sizeX-$resetW-$gap
        $customX=$resetX-$customW-$gap
        # La rangee ne demarre jamais sous le logo (zone 0-75 px reservee).
        $customX=[int][math]::Max($customX,75)
        $customButton.Location=New-Object System.Drawing.Point($customX,62)
        $resetSizeButton.Location=New-Object System.Drawing.Point($resetX,62)
        $sizeButton.Location=New-Object System.Drawing.Point($sizeX,62)
        $help.AutoSize=$false
        $help.AutoEllipsis=$false
        $help.Font=New-Object System.Drawing.Font("Segoe UI",9)
        $help.Location=New-Object System.Drawing.Point(125,5)
        $help.Size=New-Object System.Drawing.Size([math]::Max(100,$w-140),50)
    }else{
'@
    },
    @{
        Name = "P16d - En-tete : mode replie (explications et boutons masques)"
        Mandatory = $true
        Old = @'
    }else{
        $headerHeight=105
        $header.Size=New-Object System.Drawing.Size($w,$headerHeight)
        $title.Location=New-Object System.Drawing.Point(15,8)
        $help.AutoSize=$false
        $help.AutoEllipsis=$false
        $help.Font=New-Object System.Drawing.Font("Segoe UI",9)
        $help.Location=New-Object System.Drawing.Point(125,5)
        $help.Size=New-Object System.Drawing.Size([math]::Max(100,$w-140),55)

        $available=[math]::Max(90,$w-10)
        if($totalW -le $available){
            $x=[int][math]::Max(5,($w-$totalW)/2)
            $customButton.Size=New-Object System.Drawing.Size($customW,32)
            $resetSizeButton.Size=New-Object System.Drawing.Size($resetW,32)
            $sizeButton.Size=New-Object System.Drawing.Size($sizeW,32)
            $customButton.Location=New-Object System.Drawing.Point($x,62)
            $resetSizeButton.Location=New-Object System.Drawing.Point(($x+$customW+$gap),62)
            $sizeButton.Location=New-Object System.Drawing.Point(($x+$customW+$gap+$resetW+$gap),62)
        }else{
            $headerHeight=140
            $header.Size=New-Object System.Drawing.Size($w,$headerHeight)
            $buttonW=[int][math]::Max(100,($w-20)/2)
            $row1W=[int][math]::Min($buttonW,$w-10)
            $row2W=[int][math]::Min($buttonW,$w-10)
            $customButton.Size=New-Object System.Drawing.Size($row1W,32)
            $resetSizeButton.Size=New-Object System.Drawing.Size($row1W,32)
            $sizeButton.Size=New-Object System.Drawing.Size($row2W,32)
            $customButton.Location=New-Object System.Drawing.Point(5,62)
            $resetSizeButton.Location=New-Object System.Drawing.Point(($w-$row1W-5),62)
            $sizeButton.Location=New-Object System.Drawing.Point(5,100)
        }
    }
'@
        New = @'
    }else{
        $headerHeight=62
        $header.Size=New-Object System.Drawing.Size($w,$headerHeight)
        $title.Location=New-Object System.Drawing.Point(15,10)
        $help.Visible=$false
        $customButton.Visible=$false
        $resetSizeButton.Visible=$false
        $sizeButton.Visible=$false
    }
'@
    },
    @{
        Name = "P16e - En-tete : explications seulement en mode complet"
        Mandatory = $true
        Old = @'
    # Les explications sont regroupées intelligemment : sur une petite fenêtre,
    # deux explications par ligne sont privilégiées.
    $help.Text=Build-HelpText ([int]$help.Width)
    $helpLines=($help.Text -split [Environment]::NewLine).Count
    if(-not $oneLine -and $helpLines -gt 3){
        $needed=[int][math]::Max(140, 8 + ($helpLines*17) + 42)
        if($needed -gt $headerHeight){
            $headerHeight=$needed
            $header.Size=New-Object System.Drawing.Size($w,$headerHeight)
            $buttonY=$headerHeight-43
            if($totalW -le $available){
                $x=[int][math]::Max(5,($w-$totalW)/2)
                $customButton.Location=New-Object System.Drawing.Point($x,$buttonY)
                $resetSizeButton.Location=New-Object System.Drawing.Point(($x+$customW+$gap),$buttonY)
                $sizeButton.Location=New-Object System.Drawing.Point(($x+$customW+$gap+$resetW+$gap),$buttonY)
            }else{
                $customButton.Location=New-Object System.Drawing.Point(5,$buttonY-38)
                $resetSizeButton.Location=New-Object System.Drawing.Point(($w-$row1W-5),$buttonY-38)
                $sizeButton.Location=New-Object System.Drawing.Point(5,$buttonY)
            }
        }
    }
'@
        New = @'
    # Les explications ne sont construites qu en mode complet : en mode
    # replie elles sont masquees, le nom du logiciel et le logo restent seuls.
    if($oneLine){
        $help.Text=Build-HelpText ([int]$help.Width)
    }
'@
    },
    @{
        Name = "P16f - En-tete : menu contextuel du clic droit"
        Mandatory = $true
        Old = @'
$header.Controls.Add($customButton)
$header.Controls.Add($resetSizeButton)
$header.Controls.Add($sizeButton)
'@
        New = @'
$header.Controls.Add($customButton)
$header.Controls.Add($resetSizeButton)
$header.Controls.Add($sizeButton)

# P16f : clic droit dans l en-tete. Toutes les fonctions restent disponibles
# meme quand l en-tete est replie : le nom du logiciel et le logo ne sont
# jamais masques, le clic droit reste donc toujours possible sur eux.
$script:headerMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:headerMenu.ShowImageMargin = $false
$script:headerMenu.ShowCheckMargin = $true
$headerMenuCustom = $script:headerMenu.Items.Add((T-Grid "Personnaliser"))
$headerMenuReset = $script:headerMenu.Items.Add((T-Grid "Tailles par défaut"))
$headerMenuCount = $script:headerMenu.Items.Add((T-Grid "Nombre de cellules"))
[void]$script:headerMenu.Items.Add("-")
$script:headerMenuToggle = $script:headerMenu.Items.Add((T-Grid "En-tête : masquer"))
$headerMenuCustom.Add_Click({ Edit-Theme })
$headerMenuReset.Add_Click({ Reset-GridSizes })
$headerMenuCount.Add_Click({ Edit-GridDimensions })

function Update-HeaderCollapsedTexts {
    if($null -ne $script:headerMenuToggle){
        if($script:headerCollapsed){ $script:headerMenuToggle.Text=(T-Grid "En-tête : afficher") }
        else{ $script:headerMenuToggle.Text=(T-Grid "En-tête : masquer") }
        try { $script:headerMenuToggle.Checked=[bool]$script:headerCollapsed } catch { }
    }
    if($null -ne $script:headerMenuTop){
        try { $script:headerMenuTop.Checked=[bool]$form.TopMost } catch { }
    }
    if($null -ne $trayHeader){
        if($script:headerCollapsed){ $trayHeader.Text=(T-Grid "En-tête : afficher") }
        else{ $trayHeader.Text=(T-Grid "En-tête : masquer") }
    }
}

function Toggle-HeaderCollapsed {
    $script:headerCollapsed = (-not $script:headerCollapsed)
    Update-HeaderLayout
    Update-HeaderCollapsedTexts
    try { Save-Slots } catch {}
}

$script:headerMenuToggle.Add_Click({ Toggle-HeaderCollapsed })

$script:ShowHeaderMenu = {
    param($menuControl,$menuLocation)
    Update-HeaderCollapsedTexts
    $script:headerMenu.Show($menuControl, $menuLocation)
}
$header.Add_MouseDown({
    if($_.Button -eq [System.Windows.Forms.MouseButtons]::Right){
        & $script:ShowHeaderMenu $header $_.Location
    }
})
$title.Add_MouseDown({
    if($_.Button -eq [System.Windows.Forms.MouseButtons]::Right){
        & $script:ShowHeaderMenu $title $_.Location
    }
})
'@
    },
    @{
        Name = "P16g - Systray : entrees Personnaliser, Tailles, Nombre de cellules"
        Mandatory = $true
        Old = @'
    $trayOpen = $trayMenu.Items.Add("Ouvrir SniperClip")
    $trayHide = $trayMenu.Items.Add("Masquer SniperClip")
    [void]$trayMenu.Items.Add("-")
'@
        New = @'
    $trayOpen = $trayMenu.Items.Add("Ouvrir SniperClip")
    $trayHide = $trayMenu.Items.Add("Masquer SniperClip")
    [void]$trayMenu.Items.Add("-")
    $trayCustom = $trayMenu.Items.Add((T-Grid "Personnaliser"))
    $trayReset = $trayMenu.Items.Add((T-Grid "Tailles par défaut"))
    $trayCount = $trayMenu.Items.Add((T-Grid "Nombre de cellules"))
    $trayHeader = $trayMenu.Items.Add((T-Grid "En-tête : masquer"))
    [void]$trayMenu.Items.Add("-")
'@
    },
    @{
        Name = "P16h - Systray : gestionnaires des nouvelles entrees"
        Mandatory = $true
        Old = @'
    $trayOpen.Add_Click($showSniperClip)
    $trayHide.Add_Click($hideSniperClip)
'@
        New = @'
    $trayOpen.Add_Click($showSniperClip)
    $trayHide.Add_Click($hideSniperClip)
    $trayCustom.Add_Click({ & $showSniperClip; Edit-Theme })
    $trayReset.Add_Click({ & $showSniperClip; Reset-GridSizes })
    $trayCount.Add_Click({ & $showSniperClip; Edit-GridDimensions })
    $trayHeader.Add_Click({ & $showSniperClip; Toggle-HeaderCollapsed })
'@
    },
    @{
        Name = "P16i - Systray : libelles des nouvelles entrees par langue"
        Mandatory = $true
        Old = @'
        $trayQuit.Text=(T "Quitter SniperClip"); $trayExport.Text=(T "Exporter la configuration"); $trayImport.Text=(T "Importer une configuration"); $trayLog.Text=(T "Ouvrir le journal")
'@
        New = @'
        $trayQuit.Text=(T "Quitter SniperClip"); $trayExport.Text=(T "Exporter la configuration"); $trayImport.Text=(T "Importer une configuration"); $trayLog.Text=(T "Ouvrir le journal")
        $trayCustom.Text=(T-Grid "Personnaliser"); $trayReset.Text=(T-Grid "Tailles par défaut"); $trayCount.Text=(T-Grid "Nombre de cellules")
        if($null -ne $headerMenuCustom){ try { $headerMenuCustom.Text=(T-Grid "Personnaliser") } catch {} }
        if($null -ne $headerMenuReset){ try { $headerMenuReset.Text=(T-Grid "Tailles par défaut") } catch {} }
        if($null -ne $headerMenuCount){ try { $headerMenuCount.Text=(T-Grid "Nombre de cellules") } catch {} }
        Update-HeaderCollapsedTexts
        try { Update-HeaderLayout } catch {}
'@
    },
    @{
        Name = "P16j - Langue : libelle du bouton Nombre de cellules"
        Mandatory = $true
        Old = @'
        if($null -ne $sizeButton){ $sizeButton.Text=(T "Taille des cellules") }
'@
        New = @'
        if($null -ne $sizeButton){ $sizeButton.Text=(T-Grid "Nombre de cellules") }
'@
    },
    @{
        Name = "P16k - Demarrage : mise en page initiale de l en-tete"
        Mandatory = $true
        Old = @'
    $form.Add_Shown({
        if($null -ne $trayIcon){ $trayIcon.Visible=$true }
    })
'@
        New = @'
    $form.Add_Shown({
        if($null -ne $trayIcon){ $trayIcon.Visible=$true }
        try { $form.MinimumSize = New-Object System.Drawing.Size(100,240) } catch {}
        try { Update-HeaderLayout } catch {}
        try { Update-HeaderCollapsedTexts } catch {}
    })
'@
    },
    @{
        Name = "P17a - Systray : Demarrer avec Windows et Langue avant About"
        Mandatory = $true
        Old = @'
    $trayStartup = $trayMenu.Items.Add((T "Démarrer SniperClip avec Windows"))
    $trayStartup.CheckOnClick = $true
    $trayStartup.Checked = Get-StartupEnabled
    $trayStartup.AutoSize = $true
    [void]$trayMenu.Items.Add("-")
    $trayLanguage = $trayMenu.Items.Add((T "Langue"))
    $langMenu = New-Object System.Windows.Forms.ToolStripDropDownMenu
    $langFr = $langMenu.Items.Add("Français")
    $langEn = $langMenu.Items.Add("English")
    $langEs = $langMenu.Items.Add("Español")
    $langDe = $langMenu.Items.Add("Deutsch")
    $langPl = $langMenu.Items.Add("Polski")
    $langJa = $langMenu.Items.Add("日本語")
    $langIt = $langMenu.Items.Add("Italiano")
    $trayLanguage.DropDown = $langMenu
    foreach($li in @($langFr,$langEn,$langEs,$langDe,$langPl,$langJa,$langIt)){ $li.CheckOnClick = $true }
    $langFr.Checked = ($script:Language -eq "fr"); $langEn.Checked = ($script:Language -eq "en"); $langEs.Checked = ($script:Language -eq "es"); $langDe.Checked = ($script:Language -eq "de"); $langPl.Checked = ($script:Language -eq "pl"); $langJa.Checked = ($script:Language -eq "ja"); $langIt.Checked = ($script:Language -eq "it")
    [void]$trayMenu.Items.Add("-")
    $trayExport = $trayMenu.Items.Add((T "Exporter la configuration"))
    $trayImport = $trayMenu.Items.Add((T "Importer une configuration"))
    $trayLog = $trayMenu.Items.Add((T "Ouvrir le journal"))
    [void]$trayMenu.Items.Add("-")
    $trayAbout = $trayMenu.Items.Add("About SniperClip")
'@
        New = @'
    $trayExport = $trayMenu.Items.Add((T "Exporter la configuration"))
    $trayImport = $trayMenu.Items.Add((T "Importer une configuration"))
    $trayLog = $trayMenu.Items.Add((T "Ouvrir le journal"))
    [void]$trayMenu.Items.Add("-")
    $trayStartup = $trayMenu.Items.Add((T "Démarrer SniperClip avec Windows"))
    $trayStartup.CheckOnClick = $true
    $trayStartup.Checked = Get-StartupEnabled
    $trayStartup.AutoSize = $true
    [void]$trayMenu.Items.Add("-")
    $trayLanguage = $trayMenu.Items.Add((T "Langue"))
    $langMenu = New-Object System.Windows.Forms.ToolStripDropDownMenu
    $langFr = $langMenu.Items.Add("Français")
    $langEn = $langMenu.Items.Add("English")
    $langEs = $langMenu.Items.Add("Español")
    $langDe = $langMenu.Items.Add("Deutsch")
    $langPl = $langMenu.Items.Add("Polski")
    $langJa = $langMenu.Items.Add("日本語")
    $langIt = $langMenu.Items.Add("Italiano")
    $trayLanguage.DropDown = $langMenu
    foreach($li in @($langFr,$langEn,$langEs,$langDe,$langPl,$langJa,$langIt)){ $li.CheckOnClick = $true }
    $langFr.Checked = ($script:Language -eq "fr"); $langEn.Checked = ($script:Language -eq "en"); $langEs.Checked = ($script:Language -eq "es"); $langDe.Checked = ($script:Language -eq "de"); $langPl.Checked = ($script:Language -eq "pl"); $langJa.Checked = ($script:Language -eq "ja"); $langIt.Checked = ($script:Language -eq "it")
    [void]$trayMenu.Items.Add("-")
    $trayAbout = $trayMenu.Items.Add("About SniperClip")
'@
    },
    @{
        Name = "P17b - Langues : traductions natives des libelles de la grille"
        Mandatory = $true
        Old = @'
}catch { $script:LangMap=@{} }

function T([string]$text){
'@
        New = @'
}catch { $script:LangMap=@{} }

# P17b : traductions natives des libelles de la grille parametrable.
# Les cles manquantes sont ajoutees a la table de chaque langue : la
# fonction T du logiciel fait alors tout le travail de traduction,
# pour toutes les langues de l interface.
$p17LangKeys=@{
    "en"=@{
        "Nombre de cellules"="Cell count"
        "Colonnes et lignes de la grille (maximum 30 x 30)."="Grid columns and rows (maximum 30 x 30)."
        "Colonnes :"="Columns:"
        "Lignes :"="Rows:"
        "Total : "="Total: "
        " cellules"=" cells"
        "En-tête : masquer"="Header: hide"
        "En-tête : afficher"="Header: show"
        " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?"=" cells containing data will no longer be displayed. They are kept and will reappear if you enlarge the grid. Continue ?"
    }
    "es"=@{
        "Nombre de cellules"="Número de celdas"
        "Colonnes et lignes de la grille (maximum 30 x 30)."="Columnas y filas de la cuadrícula (máximo 30 x 30)."
        "Colonnes :"="Columnas:"
        "Lignes :"="Filas:"
        "Total : "="Total: "
        " cellules"=" celdas"
        "En-tête : masquer"="Encabezado: ocultar"
        "En-tête : afficher"="Encabezado: mostrar"
        " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?"=" celdas con datos dejarán de mostrarse. Se conservan y reaparecerán al ampliar la cuadrícula. ¿Continuar?"
    }
    "de"=@{
        "Nombre de cellules"="Zellanzahl"
        "Colonnes et lignes de la grille (maximum 30 x 30)."="Spalten und Zeilen des Rasters (maximal 30 x 30)."
        "Colonnes :"="Spalten:"
        "Lignes :"="Zeilen:"
        "Total : "="Gesamt: "
        " cellules"=" Zellen"
        "En-tête : masquer"="Kopfzeile: ausblenden"
        "En-tête : afficher"="Kopfzeile: anzeigen"
        " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?"=" Zellen mit Daten werden nicht mehr angezeigt. Sie bleiben erhalten und erscheinen wieder, wenn Sie das Raster vergrößern. Fortfahren?"
    }
    "pl"=@{
        "Nombre de cellules"="Liczba komórek"
        "Colonnes et lignes de la grille (maximum 30 x 30)."="Kolumny i wiersze siatki (maksymalnie 30 x 30)."
        "Colonnes :"="Kolumny:"
        "Lignes :"="Wiersze:"
        "Total : "="Łącznie: "
        " cellules"=" komórek"
        "En-tête : masquer"="Nagłówek: ukryj"
        "En-tête : afficher"="Nagłówek: pokaż"
        " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?"=" komórek zawierających dane nie będzie już wyświetlanych. Są zachowywane i pojawią się ponownie po powiększeniu siatki. Kontynuować?"
    }
    "ja"=@{
        "Nombre de cellules"="セル数"
        "Colonnes et lignes de la grille (maximum 30 x 30)."="グリッドの列と行（最大 30 x 30）。"
        "Colonnes :"="列:"
        "Lignes :"="行:"
        "Total : "="合計: "
        " cellules"=" セル"
        "En-tête : masquer"="ヘッダー: 非表示"
        "En-tête : afficher"="ヘッダー: 表示"
        " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?"=" 個のセル（データあり）は表示されなくなります。保存され、グリッドを拡大すると再び表示されます。続行しますか？"
    }
    "it"=@{
        "Nombre de cellules"="Numero di celle"
        "Colonnes et lignes de la grille (maximum 30 x 30)."="Colonne e righe della griglia (massimo 30 x 30)."
        "Colonnes :"="Colonne:"
        "Lignes :"="Righe:"
        "Total : "="Totale: "
        " cellules"=" celle"
        "En-tête : masquer"="Intestazione: nascondi"
        "En-tête : afficher"="Intestazione: mostra"
        " cellules contenant des données ne seront plus affichées. Elles sont conservées et réapparaîtront si vous agrandissez la grille. Continuer ?"=" celle contenenti dati non saranno più visualizzate. Vengono conservate e ricompaiono se si ingrandisce la griglia. Continuare?"
    }
}
foreach($p17LangName in @($p17LangKeys.Keys)){
    if(-not $script:LangMap.ContainsKey($p17LangName)){ $script:LangMap[$p17LangName]=@{} }
    $p17Table=$script:LangMap[$p17LangName]
    foreach($p17Key in @($p17LangKeys[$p17LangName].Keys)){
        if(-not $p17Table.ContainsKey($p17Key)){ $p17Table[$p17Key]=[string]$p17LangKeys[$p17LangName][$p17Key] }
    }
}

function T([string]$text){
'@
    },
    @{
        Name = "P18 - En-tete : largeur reelle des 3 boutons dans toutes les langues"
        Mandatory = $true
        Old = @'
    $customW=Localized-ButtonWidth (T "Personnaliser") 100 24
    $resetW=Localized-ButtonWidth (T "Tailles par défaut") 130 24
    $sizeW=Localized-ButtonWidth (T-Grid "Nombre de cellules") 120 24
'@
        New = @'
    $customW=Localized-ButtonWidth (T "Personnaliser") 100 24
    $resetW=Localized-ButtonWidth (T "Tailles par défaut") 130 24
    $sizeW=Localized-ButtonWidth (T-Grid "Nombre de cellules") 120 24

    # P18 : la largeur estimee peut sous-estimer le texte reel selon la
    # langue (en, es, it...). Les 3 boutons sont remesures avec leur propre
    # police et une marge large : aucun libelle n est jamais coupe, la
    # rangee de boutons a exactement la largeur de son contenu.
    $p18Graphics=$null
    try{
        $p18Graphics=$header.CreateGraphics()
        $p18Font=$customButton.Font
        if($null -ne $p18Graphics -and $null -ne $p18Font){
            $p18CustomText=[string]$customButton.Text
            $p18ResetText=[string]$resetSizeButton.Text
            $p18SizeText=[string]$sizeButton.Text
            $customW=[int][math]::Max($customW,([int][math]::Ceiling($p18Graphics.MeasureString($p18CustomText,$p18Font).Width))+30)
            $resetW=[int][math]::Max($resetW,([int][math]::Ceiling($p18Graphics.MeasureString($p18ResetText,$p18Font).Width))+30)
            $sizeW=[int][math]::Max($sizeW,([int][math]::Ceiling($p18Graphics.MeasureString($p18SizeText,$p18Font).Width))+30)
        }
    }catch{}
    try{ if($null -ne $p18Graphics){ $p18Graphics.Dispose() } }catch{}
'@
    },
    @{
        Name = "P19 - Systray : icones des entrees et total de cellules"
        Mandatory = $true
        Old = @'
    $trayHeader.Add_Click({ & $showSniperClip; Toggle-HeaderCollapsed })
'@
        New = @'
    $trayHeader.Add_Click({ & $showSniperClip; Toggle-HeaderCollapsed })

    # P19 : icones du menu systray, dessinees a l execution (aucun fichier
    # externe requis, l exe reste autonome). Les entrees sans icone
    # demandee restent telles quelles ; le libelle Nombre de cellules
    # rappele en permanence le total de cellules visibles. Les marges sont
    # resserrees au maximum pour un menu compact.
    try{
        $trayMenu.ShowImageMargin=$true
        $trayMenu.ShowCheckMargin=$false
        $trayMenu.ImageScalingSize=New-Object System.Drawing.Size(16,16)
        $trayMenu.Padding=New-Object System.Windows.Forms.Padding(0)
        foreach($ti in @($trayMenu.Items)){ try{ $ti.Padding=New-Object System.Windows.Forms.Padding(0) }catch{} }
        if($null -ne $langMenu){
            $langMenu.ShowImageMargin=$false
            $langMenu.ShowCheckMargin=$true
            $langMenu.Padding=New-Object System.Windows.Forms.Padding(0)
            foreach($li in @($langMenu.Items)){ try{ $li.Padding=New-Object System.Windows.Forms.Padding(0) }catch{} }
        }
    }catch{}

    function script:New-TrayMenuIcon([string]$kind){
        $bmp=New-Object System.Drawing.Bitmap 16,16
        $g=[System.Drawing.Graphics]::FromImage($bmp)
        try{
            $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $pen=New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(45,45,45))
            $pen.Width=2
            if($kind -eq "open"){
                if($null -ne $script:appLogoSource){
                    $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    try{ $g.DrawImage($script:appLogoSource,0,0,16,16) }catch{}
                }else{
                    $g.DrawRectangle($pen,2,4,12,9)
                    $g.DrawLine($pen,2,7,14,7)
                }
            }elseif($kind -eq "custom"){
                $g.DrawEllipse($pen,3,3,10,10)
                $g.DrawEllipse($pen,6,6,4,4)
                $g.DrawLine($pen,12,8,15,8)
                $g.DrawLine($pen,8,12,8,15)
                $g.DrawLine($pen,4,8,1,8)
                $g.DrawLine($pen,8,4,8,1)
                $g.DrawLine($pen,11,11,13,13)
                $g.DrawLine($pen,5,11,3,13)
                $g.DrawLine($pen,5,5,3,3)
                $g.DrawLine($pen,11,5,13,3)
            }elseif($kind -eq "export"){
                $g.DrawLine($pen,8,14,8,5)
                $g.DrawLine($pen,8,3,4,7)
                $g.DrawLine($pen,8,3,12,7)
            }elseif($kind -eq "import"){
                $g.DrawLine($pen,8,2,8,11)
                $g.DrawLine($pen,8,13,4,9)
                $g.DrawLine($pen,8,13,12,9)
            }elseif($kind -eq "language"){
                $g.DrawEllipse($pen,2,2,12,12)
                $g.DrawEllipse($pen,5,2,6,12)
                $g.DrawLine($pen,2,8,14,8)
            }elseif($kind -eq "quit"){
                $pen.Color=[System.Drawing.Color]::FromArgb(200,40,40)
                $pen.Width=2.5
                $g.DrawLine($pen,4,4,12,12)
                $g.DrawLine($pen,12,4,4,12)
            }
        }catch{}finally{
            try{ $g.Dispose() }catch{}
        }
        return $bmp
    }

    function script:Get-TrayCountLabel {
        $lbl=(T-Grid "Nombre de cellules")
        try{
            $cnt=0
            try{ $cnt=[int]$script:count }catch{ $cnt=0 }
            if($cnt -gt 0){ $lbl=($lbl+" ("+[string]$cnt+")") }
        }catch{}
        return $lbl
    }

    try{ if($null -ne $trayOpen){ $trayOpen.Image=(New-TrayMenuIcon "open") } }catch{}
    try{ if($null -ne $trayCustom){ $trayCustom.Image=(New-TrayMenuIcon "custom") } }catch{}
    try{ if($null -ne $trayExport){ $trayExport.Image=(New-TrayMenuIcon "export") } }catch{}
    try{ if($null -ne $trayImport){ $trayImport.Image=(New-TrayMenuIcon "import") } }catch{}
    try{ if($null -ne $trayLanguage){ $trayLanguage.Image=(New-TrayMenuIcon "language") } }catch{}
    try{ if($null -ne $trayQuit){ $trayQuit.Image=(New-TrayMenuIcon "quit") } }catch{}
    try{
        if($null -ne $trayCount){ $trayCount.Text=(Get-TrayCountLabel) }
        if($null -ne $trayMenu){
            $trayMenu.Add_Opening({
                try{ if($null -ne $trayCount){ $trayCount.Text=(Get-TrayCountLabel) } }catch{}
            })
        }
    }catch{}
'@
    },
    @{
        Name = "P20a - Cellules : echange et deplacement par glisser-deposer (logique)"
        Mandatory = $true
        Old = @'
function Update-AllButtons {
    if($buttons.Count -ne $count){return}
    for($j=0;$j -lt $count;$j++){ Update-Button $j }
}
'@
        New = @'
function Update-AllButtons {
    if($buttons.Count -ne $count){return}
    for($j=0;$j -lt $count;$j++){ Update-Button $j }
}

# P20a : echange et deplacement des cellules par glisser-deposer. Chaque
# cellule emporte tout ce qui lui est attache : nom, contenu texte, RTF,
# HTML, couleur de fond et raccourci clavier (le raccourci suit la cellule,
# il continue de copier son contenu apres l echange). Une cellule lachee
# sur une case vide y est deplacee ; lachee sur une case occupee, les deux
# cellules sont echangees. Les cellules de la reserve masquee ne sont pas
# concernées : seul l affichage visible est reorganisable a la souris.
$script:dragSourceIndex = -1
$script:dragStartPoint = $null
$script:dragPending = $false

function script:New-EmptySlot {
    return [pscustomobject]@{Name="";Text="";Rtf="";Html="";CellBack="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
}

function script:Move-CellToIndex([int]$src,[int]$dst){
    try{
        if($src -lt 0 -or $src -ge $count -or $dst -lt 0 -or $dst -ge $count){ return $false }
        if($src -eq $dst){ return $false }
        $srcSlot=$slots[$src]
        $dstSlot=$slots[$dst]
        $srcHas=$false
        $dstHas=$false
        try{ $srcHas=(Test-SlotHasData $srcSlot) }catch{}
        try{ $dstHas=(Test-SlotHasData $dstSlot) }catch{}
        if(-not $srcHas -and -not $dstHas){ return $false }
        if($dstHas){
            # Case cible occupee : echange complet des deux cellules.
            $slots[$src]=$dstSlot
            $slots[$dst]=$srcSlot
        }else{
            # Case cible vide : deplacement, la case d origine redevient vide.
            $slots[$dst]=$srcSlot
            $slots[$src]=(New-EmptySlot)
        }
        return $true
    }catch{ return $false }
}
'@
    },
    @{
        Name = "P20b - Cellules : glisser-deposer sur les boutons de la grille"
        Mandatory = $true
        Old = @'
            $contextMenu.Show($this, $_.Location)
        }
    })

    return $b
}
'@
        New = @'
            $contextMenu.Show($this, $_.Location)
        }
    })

    # P20b : glisser une cellule sur une autre pour l echanger ou la
    # deplacer. Le clic gauche simple garde son comportement (copier ou
    # editer) : le glisser ne demarre qu apres un deplacement d au moins
    # 5 pixels. Le clic droit et le redimensionnement des colonnes et des
    # lignes restent inchanges. La cellule visee se surligne en bleu pendant
    # le survol du glisser.
    try{ $b.AllowDrop=$true }catch{}
    $b.Add_MouseDown({
        try{
            if($_.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $script:isResizing){
                $script:dragStartPoint=New-Object System.Drawing.Point([int]$_.X,[int]$_.Y)
                $script:dragSourceIndex=[int]$this.Tag
                $script:dragPending=$true
            }else{
                $script:dragPending=$false
            }
        }catch{}
    })
    $b.Add_MouseMove({
        try{
            if(-not $script:dragPending){ return }
            if($script:isResizing -or [int]$this.Tag -ne $script:dragSourceIndex){
                $script:dragPending=$false
                return
            }
            if(-not ($_.Button -band [System.Windows.Forms.MouseButtons]::Left)){ return }
            $dx=([int]$_.X-[int]$script:dragStartPoint.X)
            $dy=([int]$_.Y-[int]$script:dragStartPoint.Y)
            if((($dx*$dx)+($dy*$dy)) -lt 25){ return }
            $script:dragPending=$false
            Hide-Preview
            $script:previewIndex=-1
            [void]$this.DoDragDrop(([string]$this.Tag),[System.Windows.Forms.DragDropEffects]::Move)
        }catch{}
    })
    $b.Add_MouseUp({
        try{ $script:dragPending=$false }catch{}
    })
    $b.Add_DragEnter({
        try{
            Hide-Preview
            if($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::Text)){
                $_.Effect=[System.Windows.Forms.DragDropEffects]::Move
                $this.FlatAppearance.BorderColor=[System.Drawing.Color]::FromArgb(0,120,215)
            }
        }catch{}
    })
    $b.Add_DragLeave({
        try{ $this.FlatAppearance.BorderColor=Theme-Color $theme.GridLine }catch{}
    })
    $b.Add_DragDrop({
        try{
            try{ $this.FlatAppearance.BorderColor=Theme-Color $theme.GridLine }catch{}
            Hide-Preview
            if(-not $_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::Text)){ return }
            $src=-1
            try{ $src=[int][string]$_.Data.GetData([System.Windows.Forms.DataFormats]::Text) }catch{ $src=-1 }
            if($src -lt 0 -or $src -ge $count){ return }
            $dst=[int]$this.Tag
            if(Move-CellToIndex $src $dst){
                Update-Button $src
                Update-Button $dst
                try{ Save-Slots }catch{}
                try{
                    if(Get-Command Refresh-SniperClipJumpList -ErrorAction SilentlyContinue){
                        Refresh-SniperClipJumpList
                    }
                }catch{}
                Write-SniperClipLog ("Cellule echangee ou deplacee : "+($src+1)+" vers "+($dst+1)+".")
            }
        }catch{}
    })

    return $b
}
'@
    },
    @{
        Name = "P21a - En-tete : option Toujours au-dessus (menu clic droit)"
        Mandatory = $true
        Old = @'
$script:headerMenuToggle.Add_Click({ Toggle-HeaderCollapsed })
'@
        New = @'
$script:headerMenuToggle.Add_Click({ Toggle-HeaderCollapsed })

# P21a : Toujours au-dessus. Le clic droit dans l en-tete propose de garder
# la fenetre principale visible par-dessus les autres applications. La coche
# de l entree suit l etat ; le clic simple, le clic droit et le
# glisser-deposer des cellules ne changent pas.
$p21TopKeys=@{
    "en"=@{ "Toujours au-dessus"="Always on top" }
    "es"=@{ "Toujours au-dessus"="Siempre en primer plano" }
    "de"=@{ "Toujours au-dessus"="Immer im Vordergrund" }
    "pl"=@{ "Toujours au-dessus"="Zawsze na wierzchu" }
    "ja"=@{ "Toujours au-dessus"="常に最前面" }
    "it"=@{ "Toujours au-dessus"="Sempre in primo piano" }
}
foreach($p21TopLang in @($p21TopKeys.Keys)){
    try{
        if(-not $script:LangMap.ContainsKey($p21TopLang)){ $script:LangMap[$p21TopLang]=@{} }
        $p21TopTable=$script:LangMap[$p21TopLang]
        foreach($p21TopKey in @($p21TopKeys[$p21TopLang].Keys)){
            if(-not $p21TopTable.ContainsKey($p21TopKey)){ $p21TopTable[$p21TopKey]=[string]$p21TopKeys[$p21TopLang][$p21TopKey] }
        }
    }catch{ }
}
[void]$script:headerMenu.Items.Add("-")
$script:headerMenuTop = $script:headerMenu.Items.Add((T-Grid "Toujours au-dessus"))
try { $script:headerMenuTop.Checked = [bool]$form.TopMost } catch { }
$script:headerMenuTop.Add_Click({
    try {
        $form.TopMost = (-not $form.TopMost)
        $script:headerMenuTop.Checked = [bool]$form.TopMost
        try { Save-Slots } catch { }
        try {
            if($form.TopMost){ Write-SniperClipLog "Fenetre toujours au-dessus : activee." }
            else { Write-SniperClipLog "Fenetre toujours au-dessus : desactivee." }
        } catch { }
    } catch { }
})
'@
    },
    @{
        Name = "P21b - Toujours au-dessus : libelle par langue"
        Mandatory = $true
        Old = @'
        if($null -ne $headerMenuCount){ try { $headerMenuCount.Text=(T-Grid "Nombre de cellules") } catch {} }
'@
        New = @'
        if($null -ne $headerMenuCount){ try { $headerMenuCount.Text=(T-Grid "Nombre de cellules") } catch {} }
        if($null -ne $headerMenuTop){ try { $headerMenuTop.Text=(T-Grid "Toujours au-dessus") } catch {} }
'@
    },
    @{
        Name = "P22a - Cellules : titre prioritaire, entier si possible, deux lignes"
        Mandatory = $true
        Old = @'
function Get-CellDisplayText([int]$index){
    $name=[string]$slots[$index].Name
    $text=[string]$slots[$index].Text
    if([string]::IsNullOrWhiteSpace($name)){$name=($index+1).ToString()}
    if([string]::IsNullOrWhiteSpace($text)){return $name}

    $b=$buttons[$index]
    $w=[math]::Max(30,[int]$b.Width)
    $h=[math]::Max(20,[int]$b.Height)

    # On calcule une estimation de largeur disponible en caractères.
    # Le texte est volontairement court dans la cellule : le contenu complet
    # reste disponible dans l'aperçu et l'éditeur.
    $maxChars=[int][math]::Max(8,[math]::Floor(($w-12)/7.0))
    if($maxChars -gt 70){$maxChars=70}

    $flat=($text -replace "\r?\n"," / ")

    if($h -lt 42){
        # Sur une cellule basse, une seule ligne est plus fiable que deux lignes
        # centrées verticalement qui risqueraient d'être coupées.
        $prefix=$name
        $available=[math]::Max(4,$maxChars-$prefix.Length-3)
        if(($prefix.Length+3) -lt $maxChars){
            if($flat.Length -gt $available){$flat=$flat.Substring(0,$available)+"..."}
            return $prefix+" : "+$flat
        }
        if($prefix.Length -gt $maxChars){
            return $prefix.Substring(0,[math]::Max(4,$maxChars-3))+"..."
        }
        return $prefix
    }

    # Deux lignes seulement lorsque la hauteur le permet. La première ligne
    # reste le nom, la seconde le début du contenu.
    $first=$flat
    if($first.Length -gt $maxChars){
        $first=$first.Substring(0,[math]::Max(4,$maxChars-3))+"..."
    }
    return $name+"`r`n"+$first
}
'@
        New = @'
function script:Fit-CellTextToWidth([string]$cellFitText,[System.Drawing.Font]$cellFitFont,[int]$cellFitAvailW){
    if([string]::IsNullOrEmpty($cellFitText)){ return $cellFitText }
    $cellFitAvailW=[int][math]::Max(12,$cellFitAvailW)
    try{
        if([System.Windows.Forms.TextRenderer]::MeasureText($cellFitText,$cellFitFont).Width -le $cellFitAvailW){ return $cellFitText }
        $cellFitLo=1
        $cellFitHi=$cellFitText.Length
        while($cellFitLo -lt $cellFitHi){
            $cellFitMid=[int](($cellFitLo+$cellFitHi+1)/2)
            if([System.Windows.Forms.TextRenderer]::MeasureText(($cellFitText.Substring(0,$cellFitMid)+"..."),$cellFitFont).Width -le $cellFitAvailW){ $cellFitLo=$cellFitMid }
            else{ $cellFitHi=($cellFitMid-1) }
        }
        if($cellFitLo -lt 1){ $cellFitLo=1 }
        return $cellFitText.Substring(0,$cellFitLo)+"..."
    }catch{ return $cellFitText }
}

function script:Cut-CellTextAtWidth([string]$cutText,[System.Drawing.Font]$cutFont,[int]$cutAvailW){
    # Renvoie le debut du texte qui tient dans la largeur, sans points de suspension.
    $cutAvailW=[int][math]::Max(12,$cutAvailW)
    if([string]::IsNullOrEmpty($cutText)){ return $cutText }
    try{
        if([System.Windows.Forms.TextRenderer]::MeasureText($cutText,$cutFont).Width -le $cutAvailW){ return $cutText }
        $cutLo=1
        $cutHi=$cutText.Length
        while($cutLo -lt $cutHi){
            $cutMid=[int](($cutLo+$cutHi+1)/2)
            if([System.Windows.Forms.TextRenderer]::MeasureText(($cutText.Substring(0,$cutMid)),$cutFont).Width -le $cutAvailW){ $cutLo=$cutMid }
            else{ $cutHi=($cutMid-1) }
        }
        if($cutLo -lt 1){ $cutLo=1 }
        return $cutText.Substring(0,$cutLo)
    }catch{ return $cutText }
}

function script:Wrap-CellTitleToLines([string]$wrapTitle,[System.Drawing.Font]$wrapFont,[int]$wrapAvailW){
    if([string]::IsNullOrWhiteSpace($wrapTitle)){ return $wrapTitle }
    try{
        if([System.Windows.Forms.TextRenderer]::MeasureText($wrapTitle,$wrapFont).Width -le $wrapAvailW){ return $wrapTitle }
        $wrapHead=(Cut-CellTextAtWidth $wrapTitle $wrapFont $wrapAvailW)
        $wrapSpace=$wrapTitle.LastIndexOf(" ",([math]::Min($wrapHead.Length,($wrapTitle.Length-1))))
        if($wrapSpace -gt 0){ $wrapHead=$wrapTitle.Substring(0,$wrapSpace).TrimEnd() }
        if([string]::IsNullOrEmpty($wrapHead)){ return (Fit-CellTextToWidth $wrapTitle $wrapFont $wrapAvailW) }
        $wrapRest=$wrapTitle.Substring($wrapHead.Length).TrimStart()
        if([string]::IsNullOrEmpty($wrapRest)){ return $wrapHead }
        $wrapLine2=(Fit-CellTextToWidth $wrapRest $wrapFont $wrapAvailW)
        return $wrapHead+"`r`n"+$wrapLine2
    }catch{ return (Fit-CellTextToWidth $wrapTitle $wrapFont $wrapAvailW) }
}

function script:Get-CellFitFont([double]$fitSize){
    # P24 : les polices de cellules sont creees une seule fois puis
    # reutilisees, pour eviter une allocation a chaque rafraichissement.
    if($null -eq $script:cellFitFonts){ $script:cellFitFonts=@{} }
    $fitKey=[string]$fitSize
    if(-not $script:cellFitFonts.ContainsKey($fitKey)){
        $script:cellFitFonts[$fitKey]=New-Object System.Drawing.Font("Segoe UI",$fitSize)
    }
    return $script:cellFitFonts[$fitKey]
}

function Get-CellDisplayText([int]$index){
    $name=[string]$slots[$index].Name
    $text=[string]$slots[$index].Text
    if([string]::IsNullOrWhiteSpace($name)){$name=($index+1).ToString()}

    $b=$buttons[$index]
    $w=[math]::Max(30,[int]$b.Width)
    $h=[math]::Max(20,[int]$b.Height)

    # P22 : le titre a la priorite. Il est affiche en entier sur une ligne
    # des qu il tient ; sinon il occupe les deux lignes (retour a la ligne
    # au mot pres, ou au caractere pres si besoin) et la fin est coupee au
    # bord reel de la cellule avec des points de suspension. Une cellule
    # assez haute dont le titre tient sur une ligne propose en seconde
    # ligne un apercu du debut du contenu. Le contenu complet reste
    # disponible dans l apercu au survol, dans l editeur et au clic-copier.
    $flat=($text -replace "\r?\n"," / ")
    $fitSize=10.0
    if($w -lt 120 -or $h -lt 48){$fitSize=9.0}
    if($w -lt 75 -or $h -lt 36){$fitSize=8.0}
    # P24 : police mise en cache ; elle ne doit jamais etre liberee ici.
    $fitFont=(Get-CellFitFont $fitSize)
    $fitPad=12
    $fitAvailW=[int][math]::Max(20,($w-$fitPad))
    $fitLineH=([int]$fitFont.Height)+2
    $fitLines=[int][math]::Floor(([int][math]::Max(20,$h)-10)/$fitLineH)
    if($fitLines -lt 1){ $fitLines=1 }

    if($fitLines -lt 2){
        # Cellule trop basse pour deux lignes : le titre seul, ajuste.
        return (Fit-CellTextToWidth $name $fitFont $fitAvailW)
    }

    $fitName=(Fit-CellTextToWidth $name $fitFont $fitAvailW)
    if($fitName -ne $name){
        # Le titre ne tient pas sur une ligne : il occupe les deux.
        return (Wrap-CellTitleToLines $name $fitFont $fitAvailW)
    }

    if([string]::IsNullOrWhiteSpace($flat)){ return $fitName }

    # Le titre tient sur une ligne : la seconde propose le contenu.
    $fitBody=(Fit-CellTextToWidth $flat $fitFont $fitAvailW)
    return $fitName+"`r`n"+$fitBody
}
'@
    },
    @{
        Name = "P22b - Cellules : nom seul aussi ajuste a la largeur"
        Mandatory = $true
        Old = @'
    if([string]::IsNullOrWhiteSpace([string]$slots[$index].Text)){
        $name=[string]$slots[$index].Name
        if([string]::IsNullOrWhiteSpace($name)){$name=($index+1).ToString()}
        $b.Text=$name
    }else{
        $b.Text=Get-CellDisplayText $index
    }
'@
        New = @'
    $b.Text=(Get-CellDisplayText $index)
'@
    },
    @{
        Name = "P22c - Toujours au-dessus : sauvegarde de l etat dans la base"
        Mandatory = $true
        Old = @'
                foreach($pair in @(@("Window",($window|ConvertTo-Json -Compress -Depth 6)),@("Grid",($gridConfig|ConvertTo-Json -Compress -Depth 6)),@("GridV2","1"),@("GridV3","1"),@("Theme",($theme|ConvertTo-Json -Compress -Depth 6)),@("Language",$script:Language))){
'@
        New = @'
                foreach($pair in @(@("Window",($window|ConvertTo-Json -Compress -Depth 6)),@("Grid",($gridConfig|ConvertTo-Json -Compress -Depth 6)),@("GridV2","1"),@("GridV3","1"),@("Theme",($theme|ConvertTo-Json -Compress -Depth 6)),@("Language",$script:Language),@("TopMost",$(if($form.TopMost){"1"}else{"0"})))){
'@
    },
    @{
        Name = "P22d - Toujours au-dessus : lecture de l etat au demarrage"
        Mandatory = $true
        Old = @'
$savedConfig=[pscustomobject]@{Window=$null;Grid=$null;Theme=$null}
try{
    $wj=Db-GetSetting "Window"; if($wj){$savedConfig.Window=(UnB64 $wj)|ConvertFrom-Json}
    $gj=Db-GetSetting "Grid"; if($gj){$savedConfig.Grid=(UnB64 $gj)|ConvertFrom-Json}
    $tj=Db-GetSetting "Theme"; if($tj){$savedConfig.Theme=(UnB64 $tj)|ConvertFrom-Json}
}catch{}
'@
        New = @'
$savedConfig=[pscustomobject]@{Window=$null;Grid=$null;Theme=$null}
$script:topMostSaved=$false
try{
    $wj=Db-GetSetting "Window"; if($wj){$savedConfig.Window=(UnB64 $wj)|ConvertFrom-Json}
    $gj=Db-GetSetting "Grid"; if($gj){$savedConfig.Grid=(UnB64 $gj)|ConvertFrom-Json}
    $tj=Db-GetSetting "Theme"; if($tj){$savedConfig.Theme=(UnB64 $tj)|ConvertFrom-Json}
    $tmj=Db-GetSetting "TopMost"; if($tmj -and ((UnB64 $tmj) -eq "1")){ $script:topMostSaved=$true }
}catch{}
'@
    },
    @{
        Name = "P22e - Toujours au-dessus : application a la fenetre au demarrage"
        Mandatory = $true
        Old = @'
$form.KeyPreview = $true
$form.ShowInTaskbar = $true
'@
        New = @'
$form.KeyPreview = $true
$form.ShowInTaskbar = $true
# P22 : restaurer l option Toujours au-dessus memorisee dans la base.
if($script:topMostSaved){ try{ $form.TopMost=$true }catch{} }
'@
    },
    @{
        Name = "P23a - Personnalisation : variable des boutons renommee (initialisation)"
        Mandatory = $true
        Old = @'
    $rows=@()
    for($i=0;$i -lt $items.Count;$i++){
        $key=[string]$items[$i][1]
'@
        New = @'
    # P23 : variable renommee pour ne jamais masquer le nombre de lignes de
    # la grille pendant que la fenetre de personnalisation est ouverte.
    $swatchRows=@()
    for($i=0;$i -lt $items.Count;$i++){
        $key=[string]$items[$i][1]
'@
    },
    @{
        Name = "P23b - Personnalisation : variable des boutons renommee (ajout)"
        Mandatory = $true
        Old = @'
        $colorTable.Controls.Add($sw,0,$i)
        $rows += $sw
'@
        New = @'
        $colorTable.Controls.Add($sw,0,$i)
        $swatchRows += $sw
'@
    },
    @{
        Name = "P23c - Personnalisation : variable des boutons renommee (reinitialisation)"
        Mandatory = $true
        Old = @'
    $default.Add_Click({
        $theme.HeaderBack="#F5F5F5"
        $theme.HeaderText="#000000"
        $theme.GridBack="#FFFFFF"
        $theme.CellBack="#FFFFFF"
        $theme.CellText="#000000"
        $theme.GridLine="#C0C0C0"
        for($j=0;$j -lt $rows.Count;$j++){
            $key=[string]$items[$j][1]
            $rows[$j].Text=[string]$theme.$key
            $rows[$j].BackColor=Theme-Color ([string]$theme.$key)
            $rows[$j].ForeColor=Theme-Color $theme.CellText
        }
    })
'@
        New = @'
    $default.Add_Click({
        $theme.HeaderBack="#F5F5F5"
        $theme.HeaderText="#000000"
        $theme.GridBack="#FFFFFF"
        $theme.CellBack="#FFFFFF"
        $theme.CellText="#000000"
        $theme.GridLine="#C0C0C0"
        for($j=0;$j -lt $swatchRows.Count;$j++){
            $key=[string]$items[$j][1]
            $swatchRows[$j].Text=[string]$theme.$key
            $swatchRows[$j].BackColor=Theme-Color ([string]$theme.$key)
            $swatchRows[$j].ForeColor=Theme-Color $theme.CellText
        }
    })
'@
    },
    @{
        Name = "P24a - Fenetre : detection de visibilite native (IsWindowVisible)"
        Mandatory = $true
        Old = @'
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
'@
        New = @'
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@
'@
    },
    @{
        Name = "P24b - Systray : ne pas retailler une fenetre deja visible"
        Mandatory = $true
        Old = @'
        if(-not $form.IsHandleCreated){ $form.CreateControl() }
        [SniperClipNativeWindow]::ShowWindow($form.Handle,1) | Out-Null
'@
        New = @'
        if(-not $form.IsHandleCreated){ $form.CreateControl() }
        # P24 : ne rien faire quand la fenetre est deja visible, pour ne pas
        # retailler une fenetre agrandie ou en plein ecran. SW_SHOW (5) affiche
        # une fenetre masquee sans toucher a ses dimensions actuelles.
        if(-not [SniperClipNativeWindow]::IsWindowVisible($form.Handle)){
            [SniperClipNativeWindow]::ShowWindow($form.Handle,5) | Out-Null
        }
'@
    },
    @{
        Name = "P24c - Cellules : police du bouton mise en cache"
        Mandatory = $true
        Old = @'
    $size=10.0
    if($b.Width -lt 120 -or $b.Height -lt 48){$size=9.0}
    if($b.Width -lt 75 -or $b.Height -lt 36){$size=8.0}
    $b.Font=New-Object System.Drawing.Font("Segoe UI",$size)
'@
        New = @'
    $size=10.0
    if($b.Width -lt 120 -or $b.Height -lt 48){$size=9.0}
    if($b.Width -lt 75 -or $b.Height -lt 36){$size=8.0}
    # P24 : police mise en cache, jamais allouee a chaque rafraichissement.
    $b.Font=(Get-CellFitFont $size)
'@
    },
    @{
        Name = "P24d - Effacement : la couleur de la cellule est supprimee aussi"
        Mandatory = $true
        Old = @'
            $slots[$idx]=[pscustomobject]@{Name="";Text="";Rtf="";Html="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
'@
        New = @'
            # P24 : effacement complet : la couleur personnalisee est supprimee
            # en meme temps que le contenu (cellule redevenue entierement vierge).
            $slots[$idx]=[pscustomobject]@{Name="";Text="";Rtf="";Html="";CellBack="";Shortcut="";ShortcutModifiers=0;ShortcutKey=0}
'@
    },
    @{
        Name = "P24e - Sauvegarde : conserver les dernieres bornes normales"
        Mandatory = $true
        Old = @'
$bounds=$form.Bounds
'@
        New = @'
$bounds=$form.Bounds; if([string]$form.WindowState -ne "Normal" -and $null -ne $script:lastNormalBounds){ $bounds=$script:lastNormalBounds }else{ $script:lastNormalBounds=$bounds } # P24 : bornes normales conservees
'@
    },
    @{
        Name = "P24f - Demarrage : bornes normales de reference"
        Mandatory = $true
        Old = @'
            $form.Bounds=New-Object System.Drawing.Rectangle($sx,$sy,$sw,$sh)
        }
'@
        New = @'
            $form.Bounds=New-Object System.Drawing.Rectangle($sx,$sy,$sw,$sh)
            # P24 : bornes normales de reference pour la sauvegarde.
            $script:lastNormalBounds=$form.Bounds
        }
'@
    },
    @{
        Name = "P24g - Apercu : gestionnaire duplique supprime"
        Mandatory = $true
        Old = @'
$previewMonitor.Add_Tick({
    if($script:previewIndex -lt 0){
        $previewMonitor.Stop()
        return
    }

    $idx=$script:previewIndex
    if($idx -ge $buttons.Count){
        Hide-Preview
        return
    }

    $mouse=[System.Windows.Forms.Cursor]::Position
    $cellRect=$buttons[$idx].RectangleToScreen($buttons[$idx].ClientRectangle)

    # The preview itself is deliberately ignored here: the source cell is
    # the only area that keeps the preview alive.
    if(-not $cellRect.Contains($mouse)){
        Hide-Preview
    }
})
'@
        New = @'
# P24 : gestionnaire duplique supprime. Le second Add_Tick du meme timer,
# plus fiable (coordonnees ecran et remise a zero de l index), suffit seul.
'@
    },
    @{
        Name = "P24h - About : version 1.0"
        Mandatory = $true
        Old = @'
        $version.Text = "Version 5.48k"
'@
        New = @'
        $version.Text = "Version 1.0 - Open source (licence MIT)"
'@
    },
    @{
        Name = "P24i - Export : version 1.0 dans le manifeste"
        Mandatory = $true
        Old = @'
        $manifest="SniperClip configuration export`r`nVersion=5.48k`r`nDate="+(Get-Date).ToString("o")
'@
        New = @'
        $manifest="SniperClip configuration export`r`nVersion=1.0`r`nDate="+(Get-Date).ToString("o")
'@
    },
    @{
        Name = "P25 - Demarrage : restauration de la position et de la taille de la fenetre"
        Mandatory = $true
        Old = @'
if($null -ne $savedConfig -and $null -ne $savedConfig.Window){
    try{
        $sw=[int]$savedConfig.Window.Width
        $sh=[int]$savedConfig.Window.Height
        $sx=[int]$savedConfig.Window.Left
        $sy=[int]$savedConfig.Window.Top

        $form.WindowState=[System.Windows.Forms.FormWindowState]::Normal
        $form.StartPosition="Manual"

        if($sw -ge 520 -and $sh -ge 300){
            $savedRect=New-Object System.Drawing.Rectangle($sx,$sy,$sw,$sh)
            $visible=$false
            foreach($screen in [System.Windows.Forms.Screen]::AllScreens){
                if($screen.WorkingArea.IntersectsWith($savedRect)){
                    $visible=$true
                    break
                }
            }

            if(-not $visible){
                $screen=[System.Windows.Forms.Screen]::PrimaryScreen
                $wa=$screen.WorkingArea
                $sx=$wa.Left + [math]::Max(0,[int](($wa.Width-$sw)/2))
                $sy=$wa.Top + [math]::Max(0,[int](($wa.Height-$sh)/2))
            }

            $form.Bounds=New-Object System.Drawing.Rectangle($sx,$sy,$sw,$sh)
            # P24 : bornes normales de reference pour la sauvegarde.
            $script:lastNormalBounds=$form.Bounds
        }

        if($null -ne $savedConfig.Window.State){
            try{
                $savedState=[System.Windows.Forms.FormWindowState]$savedConfig.Window.State
                if($savedState -ne [System.Windows.Forms.FormWindowState]::Minimized){
                    $form.WindowState=$savedState
                }
            }catch{}
        }
    }catch{}
}
'@
        New = @'
if($null -eq $savedConfig.Window){
    Write-SniperClipLog "Fenetre : aucune position sauvegardee dans la base."
}else{
    try{
        $sw=[int]$savedConfig.Window.Width
        $sh=[int]$savedConfig.Window.Height
        $sx=[int]$savedConfig.Window.Left
        $sy=[int]$savedConfig.Window.Top

        $form.WindowState=[System.Windows.Forms.FormWindowState]::Normal
        $form.StartPosition="Manual"

        if($sw -ge 520 -and $sh -ge 300){
            $savedRect=New-Object System.Drawing.Rectangle($sx,$sy,$sw,$sh)
            $visible=$false
            foreach($screen in [System.Windows.Forms.Screen]::AllScreens){
                if($screen.WorkingArea.IntersectsWith($savedRect)){
                    $visible=$true
                    break
                }
            }

            if(-not $visible){
                $screen=[System.Windows.Forms.Screen]::PrimaryScreen
                $wa=$screen.WorkingArea
                $sx=$wa.Left + [math]::Max(0,[int](($wa.Width-$sw)/2))
                $sy=$wa.Top + [math]::Max(0,[int](($wa.Height-$sh)/2))
            }

            $form.Bounds=New-Object System.Drawing.Rectangle($sx,$sy,$sw,$sh)
            # P24 : bornes normales de reference pour la sauvegarde.
            $script:lastNormalBounds=$form.Bounds
            # P25 : bornes conservees pour la reaplication a l affichage.
            $script:restoreBounds=New-Object System.Drawing.Rectangle($sx,$sy,$sw,$sh)
            Write-SniperClipLog ("Fenetre : restauration demandee X="+$sx+" Y="+$sy+" L="+$sw+" H="+$sh)
        }

        if($null -ne $savedConfig.Window.State){
            try{
                $savedState=[System.Windows.Forms.FormWindowState]$savedConfig.Window.State
                if($savedState -ne [System.Windows.Forms.FormWindowState]::Minimized){
                    $form.WindowState=$savedState
                }
            }catch{}
        }
    }catch{
        Write-SniperClipLog ("Fenetre : echec de restauration ("+$_.Exception.Message+")") "ERROR"
    }
}

# P25 : reaplication des bornes au moment de l affichage de la fenetre.
# Les bornes definies avant l affichage peuvent etre annulees au moment ou
# la fenetre est reellement montee. Le gestionnaire Load se declenche juste
# avant la visibilite : il reapplique les bornes sauvegardees en derniere
# autorite.
$form.Add_Load({
    try{
        if($null -ne $script:restoreBounds -and [string]$form.WindowState -eq "Normal"){
            $form.StartPosition="Manual"
            $form.Bounds=$script:restoreBounds
            Write-SniperClipLog ("Fenetre : bornes reappliquees X="+$script:restoreBounds.X+" Y="+$script:restoreBounds.Y+" L="+$script:restoreBounds.Width+" H="+$script:restoreBounds.Height)
        }
    }catch{
        Write-SniperClipLog ("Fenetre : echec de la reaplication ("+$_.Exception.Message+")") "ERROR"
    }
})
'@
    },
    @{
        Name = "P26 - About : formulation de la mention de garantie"
        Mandatory = $true
        Old = @'
        $disclaimer.Text = "SniperClip is free software and comes without any warranty."
'@
        New = @'
        $disclaimer.Text = "SniperClip is free, open-source software, provided as is, without any warranty."
'@
    },
    @{
        Name = "P27 - Journal : version dans la ligne de demarrage"
        Mandatory = $true
        Old = @'
 SniperClip. Langue="+$script:Language)
'@
        New = @'
 SniperClip 1.0. Langue="+$script:Language)
'@
    }
)

$failed = @()
foreach ($p in $patches) {
    $old = ($p.Old -replace "`r`n", "`n").TrimEnd("`r", "`n")
    $new = ($p.New -replace "`r`n", "`n").TrimEnd("`r", "`n")
    $count = [regex]::Matches($text, [regex]::Escape($old)).Count
    if ($count -eq 1) {
        $text = $text.Replace($old, $new)
        Write-Host ("Correctif applique : " + $p.Name) -ForegroundColor Green
    } else {
        Write-Host ("Correctif NON TROUVE (" + $count + " occurrence(s)) : " + $p.Name) -ForegroundColor $(if ($p.Mandatory) { "Red" } else { "Yellow" })
        if ($p.Mandatory) { $failed += $p.Name }
    }
}
if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "ABANDON : votre SniperClip.ps1 differe de la version attendue." -ForegroundColor Red
    Write-Host "Correctifs en echec : $($failed -join ', ')" -ForegroundColor Red
    Write-Host "Verifiez que vous utilisez bien la version 5.48k du script," -ForegroundColor Red
    Write-Host "ou signalez la liste ci-dessus pour adaptation du kit." -ForegroundColor Red
    exit 1
}

# -------------------------------------------------------------
# 4. Integration du logo PNG (fenetre About) dans l exe
# -------------------------------------------------------------
if (Test-Path -LiteralPath $Logo) {
    $logoB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Logo))
    $token = '$script:LogoB64 = ""'
    if ($text.Contains($token)) {
        $text = $text.Replace($token, ('$script:LogoB64 = "' + $logoB64 + '"'))
        Write-Host "Logo PNG integre dans l exe (base64)." -ForegroundColor Green
    } else {
        Write-Host "Logo non integre : correctif P1 absent." -ForegroundColor Yellow
    }
}

# -------------------------------------------------------------
# 5. Ecriture de la copie compilee (UTF-8 avec BOM)
# -------------------------------------------------------------
if (Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Patched = Join-Path $BuildDir "SniperClip.compiled.ps1"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Patched, $text, $utf8Bom)
Write-Host "Copie adaptee : $Patched"

# -------------------------------------------------------------
# 6. Installation de ps2exe si necessaire
# -------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installation du module ps2exe (necessite une connexion Internet)..."
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null } catch {}
    }
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

# -------------------------------------------------------------
# 7. Compilation
# -------------------------------------------------------------
if (-not (Test-Path -LiteralPath $DistDir)) { New-Item -ItemType Directory -Force -Path $DistDir | Out-Null }
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }

$ps2exeArgs = @{
    inputFile   = $Patched
    outputFile  = $Out
    noConsole   = $true
    sta         = $true
    title       = "SniperClip"
    description = "Lightweight clipboard manager for Windows"
    product     = "SniperClip"
    company     = $CompanyName
    copyright   = "(c) 2026 " + $CompanyName
    version     = $AppVersion
}
if (Test-Path -LiteralPath $Ico) { $ps2exeArgs.iconFile = $Ico }

Write-Host "Compilation ps2exe en cours..."
Invoke-ps2exe @ps2exeArgs

if (-not (Test-Path -LiteralPath $Out)) {
    Write-Host "ERREUR : l exe n a pas ete genere." -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "Exe genere : $Out" -ForegroundColor Green
Write-Host ("Taille     : {0:N0} octets" -f (Get-Item -LiteralPath $Out).Length)

# -------------------------------------------------------------
# 7bis. Copie des fichiers de distribution open source
# -------------------------------------------------------------
# Si les fichiers LICENSE et README.md existent a cote de SniperClip.ps1,
# ils sont copies a cote de l exe dans dist\ (licence MIT).
foreach ($f in @("LICENSE", "README.md")) {
    $srcF = Join-Path $Root $f
    if (Test-Path -LiteralPath $srcF) {
        Copy-Item -LiteralPath $srcF -Destination (Join-Path $DistDir $f) -Force
        Write-Host ("Fichier open source copie dans dist : " + $f) -ForegroundColor Green
    }
}

# -------------------------------------------------------------
# 8. Signature (optionnelle)
# -------------------------------------------------------------
if ($Sign) {
    $cert = $null
    if ($Thumbprint) {
        $cert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
    }
    if (-not $cert) {
        $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
                Select-Object -First 1
    }
    if (-not $cert -and $SelfSigned) {
        Write-Host "Creation d un certificat auto-signe (confiance sur CE PC uniquement)..."
        $cert = New-SelfSignedCertificate -Subject ("CN=SniperClip - " + $CompanyName) -Type CodeSigningCert -CertStoreLocation "Cert:\CurrentUser\My"
        foreach ($storeName in @("Root", "TrustedPublisher")) {
            try {
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, "CurrentUser")
                $store.Open("ReadWrite")
                $store.Add($cert)
                $store.Close()
            } catch {}
        }
        Write-Host ("Certificat cree, empreinte : " + $cert.Thumbprint) -ForegroundColor Green
        Write-Host "Note : pour d autres PC, ce certificat doit y etre importe," -ForegroundColor Yellow
        Write-Host "sinon preferez un certificat OV/EV achete chez une autorite." -ForegroundColor Yellow
    }
    if ($cert) {
        Write-Host "Signature de SniperClip.exe (avec horodatage)..."
        $sig = Set-AuthenticodeSignature -FilePath $Out -Certificate $cert -TimestampServer "http://timestamp.digicert.com"
        if ($sig.Status -eq "Valid") {
            Write-Host "Signature : OK" -ForegroundColor Green
        } else {
            Write-Host ("Echec de la signature : " + $sig.Status + " - " + $sig.StatusMessage) -ForegroundColor Red
        }
    } else {
        Write-Host "Aucun certificat de signature de code disponible." -ForegroundColor Yellow
        Write-Host "Relancez avec -SelfSigned, ou avec -Thumbprint <empreinte> d un certificat OV/EV." -ForegroundColor Yellow
    }
}

# -------------------------------------------------------------
# 9. Resume
# -------------------------------------------------------------
Write-Host ""
Write-Host "=================== RESUME ===================" -ForegroundColor Cyan
Write-Host "Executable autonome : $Out"
Write-Host "Donnees             : %APPDATA%\SniperClip (base, sauvegarde, journal)"
Write-Host "Fichiers requis a cote de l exe : AUCUN (icone et logo integres)"
Write-Host "Licence             : MIT (Open source - voir LICENSE dans dist)"
Write-Host "Sources originales  : intouchées"
if ($Sign) {
    $finalSig = Get-AuthenticodeSignature -FilePath $Out
    Write-Host ("Signature finale    : " + $finalSig.Status)
}
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Testez l exe. En cas d alerte antivirus/SmartScreen au premier lancement :" 
Write-Host " - SmartScreen : 'Informations complementaires' > 'Executer quand meme' ;"
Write-Host " - Faux positif : soumettez l exe a Microsoft :" 
Write-Host "   https://www.microsoft.com/wdsi/filesubmission"