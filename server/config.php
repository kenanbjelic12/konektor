<?php
// Copy this file to config.php (next to api.php) and change the token.
// Never commit config.php.
return [
    // A long random secret. The app must send the same value.
    // Generate one at https://www.random.org/strings/ or in PowerShell:
    //   -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 40 | % {[char]$_})
    'token' => 'kakarot123',

    // Where uploaded files are kept. The default is a folder in your
    // Hostinger home directory, next to public_html, so nobody can open the
    // files from a browser.
    'storage_dir' => dirname(__DIR__, 2) . '/konektor-files',
];
