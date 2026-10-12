# Production Count1 prerequisite guard for Count20 staging.
Set-StrictMode -Version Latest
function Get-Count20CertificateItem([string]$Path,[int64]$Limit=4194304){
 $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($i.PSIsContainer -or $i.LinkType -or (($i.Attributes-band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $Limit){throw ('Count1 certificate must be bounded regular non-reparse file: '+$Path)}
 return $i
}
function Get-Count20CertificateHash([string]$Path,[int64]$Limit=67108864){
 $i=Get-Count20CertificateItem $Path $Limit;$stream=$null;$sha=$null;$total=0L
 try{$stream=[IO.File]::Open($i.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$sha=[Security.Cryptography.SHA256]::Create();$buffer=New-Object byte[] 1048576;while(($read=$stream.Read($buffer,0,$buffer.Length))-gt 0){$sha.TransformBlock($buffer,0,$read,$buffer,0)|Out-Null;$total+=$read;if($total -gt $Limit){throw 'Count1 certificate hash limit exceeded'}};$sha.TransformFinalBlock($buffer,0,0)|Out-Null;if($total -ne [int64]$i.Length){throw 'Count1 certificate changed while hashing'};return ([BitConverter]::ToString($sha.Hash)-replace '-','').ToLowerInvariant()}finally{if($sha){$sha.Dispose()};if($stream){$stream.Dispose()}}
}
function Read-Count20CertificateJson([string]$Path){$i=Get-Count20CertificateItem $Path 4194304;return [IO.File]::ReadAllText($i.FullName,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json}
function Assert-Count20OriginalCount1Certificate([string]$Path,[string]$ExpectedHash,[int64]$ExpectedBytes){
 $i=Get-Count20CertificateItem $Path 4194304;$expected=(($ExpectedHash-replace '^sha256:','').ToLowerInvariant());if($i.Length -ne $ExpectedBytes -or (Get-Count20CertificateHash $Path)-cne $expected){throw 'Original Count1 certificate bytes/hash mismatch'}
 $doc=Read-Count20CertificateJson $Path;foreach($name in @('count','status','taskParentProof','wholeBatchExitConfirmed','lockReleased','error','cleanupErrors')){if(-not($doc.PSObject.Properties.Name -contains $name)){throw ('Original Count1 certificate field missing: '+$name)}}
 if($doc.count -ne 1 -or $doc.status -cne 'completed-source-bound-observation'){throw 'Original certificate is not successful Count1 coordinator receipt'}
 if($doc.wholeBatchExitConfirmed -ne $true -or $doc.lockReleased -ne $true){throw 'Original Count1 whole-batch/lock proof not confirmed'}
 if(-not [string]::IsNullOrEmpty([string]$doc.error)-or @($doc.cleanupErrors).Count -ne 0){throw 'Original Count1 coordinator contains failure/cleanup errors'}
 $parent=$doc.taskParentProof;foreach($name in @('pid','retainedHandle','kernelWait','kernelExitCode','kernelExitCodeSigned','dotNetExited','dotNetExitCode')){if(-not($parent.PSObject.Properties.Name -contains $name)){throw ('Original parent proof field missing: '+$name)}}
 if($parent.pid -le 0 -or $parent.retainedHandle -le 0 -or $parent.kernelWait -ne 0 -or $parent.kernelExitCode -ne 0 -or $parent.kernelExitCodeSigned -ne 0 -or $parent.dotNetExited -ne $true -or $parent.dotNetExitCode -ne 0){throw 'Original retained parent kernel/.NET exit proof is not zero/successful'}
 return $doc
}
