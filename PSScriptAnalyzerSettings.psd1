# Livn Tools - PSScriptAnalyzer ayarlari
# Hedef: Windows PowerShell 5.1 (Windows 10/11) ile tam uyumluluk.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Kurulum ve UI konsol ciktilari icin bilincli kullanim
        'PSAvoidUsingWriteHost',
        # Ic fonksiyonlar; onay UI'da (onizleme + onay penceresi) alinir
        'PSUseShouldProcessForStateChangingFunctions',
        # Turkce kullanici metinleri; BOM kontrolu ayri testte (tests/Static.Tests.ps1)
        'PSUseBOMForUnicodeEncodedFile',
        # Saglayici/temizlik scriptblock'lari ortak imza (param($a), param($ctx,$cancel)) kullanir
        'PSReviewUnusedParameter',
        # Adlandirma stili; islevsel etkisi yok (Get-LtLedgerEntries vb.)
        'PSUseSingularNouns'
    )
    Rules        = @{
        PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @('5.1', '7.0') }
        PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework') }
        PSUseCompatibleTypes    = @{ Enable = $true; TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework') }
    }
}
