# Use the Windows Registry to find GnuPG's location

## Are we on a Win64 system?
If (Test-Path "HKLM:\Software\WOW6432Node") {
	$regroot = "HKLM:\Software\WOW6432Node\"
}
Else {
	$regroot = "HKLM:\Software\"
}

## Start by looking for GnuPG 2.1.  If we can't find
## it, fall back to looking for 2.0.

$gnupg21 = $regroot + "GnuPG"
$gnupg20 = $regroor + "GNU\GnuPG"

If (Test-Path $gnupg21) {
	$gpgdir = Join-Path `
		-Path `
			(Get-ItemPropertyValue `
				-Path "HKLM:\Software\WOW6432Node\GnuPG" `
				"Install Directory") `
		-ChildPath "bin"
	$gpg = Join-Path -Path $gpgdir "gpg.exe"
}
ElseIf (Test-Path $gnupg20) {
	$gpgdir = Get-ItemPropertyValue `
		-Path "HKLM:\Software\WOW6432Node\Gnu\GnuPG" `
		"Install Directory"
	$gpg = Join-Path -Path $gpgdir "gpg2.exe"
}

# Create the two Lists we're going to use to store the 
# revoked/expired private keys and the revoked/expired
# public keys
$private_keys = New-Object `
	-TypeName System.Collections.Generic.List[string]
$public_keys = New-Object `
	-TypeName System.Collections.Generic.List[string]

# Many of our "expired" keys will have new, duration-
# extending signatures.  We do a keyring refresh from the
# keyservers to ensure we don't delete anything we don't
# have to.
&$gpg --keyserver pool.sks-keyservers.net `
	--refresh

# Get the expired/revoked private and public keys
(&$gpg --keyid-format long `
	--fixed-list-mode `
	--with-colons --list-key | `
	Select-String -Pattern "^pub:(r|e)").ForEach({
	$match = [regex]::match($_, "([A-F0-9]{16})")
    $keyid = $match.Groups[1].Value
	$public_keys.Add($keyid)
	}
)

## In GnuPG 2.0, you can't figure out whether a private
## key is expired except by looking at its corresponding
## public key.  In GnuPG 2.1, you can, but the old way
## still works.  This code will therefore work with both.
If ($public_keys.Count -gt 0) {
	(&$gpg --keyid-format long `
		--fixed-list-mode `
		--with-colons --list-secret-key $public_keys | `
		Select-String -Pattern "^sec").ForEach({
		$match = [regex]::match($_, "([A-F0-9]{16})")
		$keyid = $match.Groups[1].Value
		$private_keys.Add($keyid)
		}
	)
}

# If we have revoked/expired private keys, get rid 
# of them first.
if ($private_keys.Count -gt 0) {
	&$gpg --yes --delete-secret-keys $private_keys
}
# Follow up with revoked/expired public keys
if ($public_keys.Count -gt 0) {
	&$gpg --yes --delete-keys $public_keys
}
