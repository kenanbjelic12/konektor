<?php
/**
 * Konektor file API: list, upload, download and delete files.
 *
 * Upload this file and config.php to public_html/konektor/ on Hostinger.
 * Every request must send the header  X-Konektor-Token: <your token>.
 *
 *   GET  api.php?action=list
 *   POST api.php?action=upload          (multipart form, field "file")
 *   GET  api.php?action=download&name=X
 *   POST api.php?action=delete&name=X
 */

declare(strict_types=1);

$config = require __DIR__ . '/config.php';

function fail(int $code, string $message): void
{
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode(['error' => $message]);
    exit;
}

function ok(array $data = []): void
{
    header('Content-Type: application/json');
    echo json_encode(['ok' => true] + $data);
    exit;
}

/** Accept a plain file name only: no folders, no hidden files. */
function safe_name(?string $name): string
{
    $name = trim((string)$name);
    if ($name === '' || $name !== basename($name) || $name[0] === '.'
        || strlen($name) > 255 || preg_match('/[\x00-\x1f\\\\\/:*?"<>|]/', $name)) {
        fail(400, 'Invalid file name');
    }
    return $name;
}

// --- Auth ---------------------------------------------------------------
$token = $_SERVER['HTTP_X_KONEKTOR_TOKEN'] ?? '';
if (strlen($config['token']) < 24 || str_contains($config['token'], 'CHANGE_ME')) {
    fail(500, 'Server token is not set. Edit config.php.');
}
if (!hash_equals($config['token'], $token)) {
    fail(401, 'Wrong token');
}

// --- Storage folder -----------------------------------------------------
$dir = rtrim($config['storage_dir'], '/');
if (!is_dir($dir) && !mkdir($dir, 0750, true)) {
    fail(500, 'Cannot create storage folder');
}
// In case the folder ends up inside public_html, block direct web access.
if (!file_exists("$dir/.htaccess")) {
    file_put_contents("$dir/.htaccess", "Require all denied\nDeny from all\n");
}

$action = $_GET['action'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];

switch ($action) {
    case 'list':
        $files = [];
        foreach (scandir($dir) as $entry) {
            $path = "$dir/$entry";
            if ($entry[0] === '.' || !is_file($path)) {
                continue;
            }
            $files[] = ['name' => $entry, 'size' => filesize($path), 'modified' => filemtime($path)];
        }
        ok(['files' => $files]);

    case 'upload':
        if ($method !== 'POST') fail(405, 'Use POST');
        $file = $_FILES['file'] ?? null;
        if ($file === null) {
            fail(413, 'No file received. It may be larger than the server upload limit ('
                . ini_get('upload_max_filesize') . ').');
        }
        if ($file['error'] !== UPLOAD_ERR_OK) {
            $tooBig = in_array($file['error'], [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true);
            fail($tooBig ? 413 : 500, $tooBig
                ? 'File is larger than the server upload limit (' . ini_get('upload_max_filesize') . ')'
                : 'Upload failed (code ' . $file['error'] . ')');
        }
        $name = safe_name($_POST['name'] ?? $file['name']);
        if (!move_uploaded_file($file['tmp_name'], "$dir/$name")) {
            fail(500, 'Could not save file');
        }
        ok(['name' => $name]);

    case 'download':
        $name = safe_name($_GET['name'] ?? null);
        $path = "$dir/$name";
        if (!is_file($path)) fail(404, 'File not found');
        // Send the file in chunks without compression or buffering, so the
        // app sees progress right away and gets an exact Content-Length.
        @ini_set('zlib.output_compression', 'Off');
        @ini_set('output_buffering', '0');
        @set_time_limit(0);
        while (ob_get_level()) ob_end_clean();
        header('Content-Type: application/octet-stream');
        header('Content-Length: ' . filesize($path));
        header('Content-Encoding: identity');
        header('Cache-Control: no-store');
        header('X-Accel-Buffering: no');
        header('Content-Disposition: attachment; filename="' . rawurlencode($name) . '"');
        $fh = fopen($path, 'rb');
        while (!feof($fh)) {
            echo fread($fh, 1024 * 1024);
            flush();
        }
        fclose($fh);
        exit;

    case 'delete':
        if ($method !== 'POST') fail(405, 'Use POST');
        $name = safe_name($_GET['name'] ?? null);
        $path = "$dir/$name";
        if (!is_file($path)) fail(404, 'File not found');
        if (!unlink($path)) fail(500, 'Could not delete file');
        ok();

    default:
        fail(400, 'Unknown action');
}
