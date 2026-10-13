# Test-sign the unsigned tuple 12 MSIX with a throwaway self-signed certificate (Subject = the manifest Publisher). Not a release signature.
$ErrorActionPreference = 'Stop'
$dir = 'D:\Claude\sr0-tuple12-pkg'
$unsigned = Join-Path $dir 'SliceApp_0.1.0.0_x64.unsigned.msix'
$signed = Join-Path $dir 'SliceApp_0.1.0.0_x64.testsigned.msix'
$subject = 'CN=Damned Ventures LLC, O=Damned Ventures LLC, L=new york, S=New York, C=US'
$cert = New-SelfSignedCertificate -Type Custom -Subject $subject -KeyUsage DigitalSignature -FriendlyName 'tuple12-test-signer' -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddDays(7) -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
try {
    $pw = ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -AsPlainText -Force
    $pfx = Join-Path $dir 'test-signer.pfx'
    Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $pw | Out-Null
    Export-Certificate -Cert $cert -FilePath (Join-Path $dir 'test-signer.cer') | Out-Null
    Copy-Item $unsigned $signed -Force
    $plain = [System.Net.NetworkCredential]::new('', $pw).Password
    & 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe' sign /fd SHA256 /f $pfx /p $plain $signed
    if ($LASTEXITCODE -ne 0) { throw "signtool exit $LASTEXITCODE" }
    Remove-Item $pfx -Force
} finally {
    Remove-Item ("Cert:\CurrentUser\My\" + $cert.Thumbprint) -Force -ErrorAction SilentlyContinue
}
"signed $signed thumbprint $($cert.Thumbprint) subject $($cert.Subject)"
(Get-FileHash $signed -Algorithm SHA256).Hash
