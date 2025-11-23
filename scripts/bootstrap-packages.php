#!/usr/bin/env php
<?php

/**
 * HelioNET Dynamic Package Loader (file-only, no DB)
 *
 * Usage:
 *   php scripts/bootstrap-packages.php [packages_file] [project_root]
 *
 * Defaults:
 *   packages_file:  __DIR__ . '/../storage/packages/packages.jsonl'
 *   project_root:   __DIR__ . '/..'
 */

declare(strict_types=1);

$defaultPackagesFile = __DIR__ . '/../storage/packages/packages.jsonl';
$defaultProjectRoot  = realpath(__DIR__ . '/..') ?: (__DIR__ . '/..');

$packagesFile = $argv[1] ?? $defaultPackagesFile;
$projectRoot  = $argv[2] ?? $defaultProjectRoot;

// Make sure errors are visible in logs
ini_set('display_errors', 'stderr');
error_reporting(E_ALL);

require __DIR__ . '/PackageDirectory.php';

logMsg("INFO", "HelioNET package bootstrap starting...");
logMsg("INFO", "Using packages file: {$packagesFile}");
logMsg("INFO", "Project root: {$projectRoot}");

$directory = new PackageDirectory($packagesFile);
$packages  = $directory->load();

if (empty($packages)) {
    logMsg("INFO", "No packages defined in directory. Nothing to do.");
    exit(0);
}

foreach ($packages as $index => &$pkg) {
    $type    = $pkg['type']    ?? 'Custom';
    $status  = $pkg['status']  ?? 'New';
    $repo    = $pkg['repo']    ?? null;
    $version = $pkg['version'] ?? null;

    if (!$repo) {
        logMsg("WARN", "Skipping entry #{$index}: missing 'repo' field.");
        continue;
    }

    $label = "{$repo}" . ($version ? ":{$version}" : '');

    switch ($status) {
        case 'Installed':
            logMsg("INFO", "[{$label}] already Installed. Skipping.");
            break;

        case 'Disabled':
            logMsg("INFO", "[{$label}] is Disabled. Skipping.");
            break;

        case 'Build-Fail':
            logMsg("INFO", "[{$label}] previously Build-Fail. Skipping.");
            break;

        case 'Error-Fail':
            logMsg("INFO", "[{$label}] previously Error-Fail. Skipping.");
            break;

        case 'Built':
            logMsg("INFO", "[{$label}] in Built state (likely concurrent install). Skipping.");
            break;

        case 'New':
        default:
            logMsg("INFO", "[{$label}] New package discovered. Attempting install...");
            [$success, $output] = runComposerRequire($projectRoot, $repo, $version);

            if (!$success) {
                $shortError = shortenOutput($output);
                $pkg['status']  = 'Build-Fail';
                $pkg['comment'] = trim(($pkg['comment'] ?? '') . ' | build-fail: ' . $shortError);
                logMsg("ERROR", "[{$label}] composer require failed. Marked Build-Fail. Error: {$shortError}");
                break;
            }

            // Mark as Built first
            $pkg['status'] = 'Built';
            logMsg("INFO", "[{$label}] composer require succeeded. Marked Built.");

            // Health check stub (always OK for now)
            if (!healthCheckStub($projectRoot, $repo, $version)) {
                $pkg['status']  = 'Error-Fail';
                $pkg['comment'] = trim(($pkg['comment'] ?? '') . ' | health-check failed');
                logMsg("ERROR", "[{$label}] health-check failed. Marked Error-Fail.");
                break;
            }

            $pkg['status'] = 'Installed';
            logMsg("INFO", "[{$label}] health-check OK. Marked Installed.");

            echo "[helionet] Running Laravel post-install maintenance...";

            // -------------------------------------------
            // SAFE post-install Artisan commands
            // -------------------------------------------

            logMsg("INFO", "[{$label}] Running post-install artisan tasks...");

            runArtisan($projectRoot, 'migrate --force');
            runArtisan($projectRoot, 'vendor:publish --all --force');

            runArtisan($projectRoot, 'config:clear');
            runArtisan($projectRoot, 'cache:clear');
            runArtisan($projectRoot, 'view:clear');
            runArtisan($projectRoot, 'route:clear');

            runArtisan($projectRoot, 'config:cache');
            runArtisan($projectRoot, 'route:cache');
            runArtisan($projectRoot, 'view:cache');

            break;
    }
}
unset($pkg); // break reference

// Save updated statuses back to file
$directory->save($packages);
logMsg("INFO", "HelioNET package bootstrap finished.");
exit(0);

/**
 * Runs an artisan command as a separate process.
 */
function runArtisan(string $projectRoot, string $command): void
{
    $cmd = "cd {$projectRoot} && php artisan {$command} 2>&1";
    $output = shell_exec($cmd);

    if ($output === null) {
        logMsg("ERROR", "Artisan command failed to run: {$command}");
        return;
    }

    logMsg("INFO", "Artisan output [{$command}]: " . trim($output));
}

/**
 * Run `composer require` for a given package.
 *
 * @return array{0:bool,1:string} [success, output]
 */
function runComposerRequire(string $projectRoot, string $repo, ?string $version): array
{
    $pkgSpec = $repo . ($version ? (':' . $version) : '');
    $cmd = sprintf(
        'cd %s && composer require %s --no-interaction --no-progress 2>&1',
        escapeshellarg($projectRoot),
        escapeshellarg($pkgSpec)
    );

    return runCommand($cmd);
}

/**
 * Stub health-check. Always returns true for now.
 * Replace later with something like:
 *   php artisan helionet:package-health-check vendor/package
 */
function healthCheckStub(string $projectRoot, string $repo, ?string $version): bool
{
    // For now: no-op health-check.
    // You could later implement:
    // $cmd = sprintf(
    //     'cd %s && php artisan helionet:package-health-check %s 2>&1',
    //     escapeshellarg($projectRoot),
    //     escapeshellarg($repo)
    // );
    // [$success, $output] = runCommand($cmd);
    // if (!$success) { logMsg("ERROR", "..."); }
    // return $success;

    return true;
}

/**
 * Run a shell command and capture success + full output.
 *
 * @return array{0:bool,1:string}
 */
function runCommand(string $cmd): array
{
    logMsg("DEBUG", "Executing: {$cmd}");
    $output = [];
    $exitCode = 0;

    exec($cmd, $output, $exitCode);

    $out = implode(PHP_EOL, $output);
    return [$exitCode === 0, $out];
}

/**
 * Shorten long command output for comments / logs.
 */
function shortenOutput(string $output, int $maxLen = 200): string
{
    $output = trim(preg_replace('/\s+/', ' ', $output));
    if (strlen($output) <= $maxLen) {
        return $output;
    }
    return substr($output, 0, $maxLen - 3) . '...';
}

/**
 * Simple log helper in a consistent format.
 */
function logMsg(string $level, string $message): void
{
    $ts = date('Y-m-d H:i:s');
    $env = getenv('APP_ENV') ?: 'local';

    // Example: [2025-11-22 12:34:56] local.INFO: [HelioNET | Packages] message
    fprintf(
        STDERR,
        "[%s] %s.%s: [HelioNET | Packages] %s%s",
        $ts,
        $env,
        strtoupper($level),
        $message,
        PHP_EOL
    );
}
