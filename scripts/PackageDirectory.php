<?php
/**
 * HelioNET Dynamic Package Directory Helper
 *
 * Flat-file JSONL storage, no DB.
 */
class PackageDirectory
{
    private string $path;

    public function __construct(string $path)
    {
        $this->path = $path;
        $this->ensureFileExists();
    }

    /**
     * Load all package entries from the JSONL file.
     *
     * @return array<int,array<string,mixed>>
     */
    public function load(): array
    {
        $packages = [];

        $fh = fopen($this->path, 'c+');
        if (!$fh) {
            throw new RuntimeException("Unable to open package directory file: {$this->path}");
        }

        try {
            // Shared lock for reading
            if (!flock($fh, LOCK_SH)) {
                throw new RuntimeException("Unable to acquire shared lock on {$this->path}");
            }

            rewind($fh);
            while (($line = fgets($fh)) !== false) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, '#')) {
                    continue;
                }

                $decoded = json_decode($line, true);
                if (!is_array($decoded)) {
                    // Optionally log malformed line and skip
                    continue;
                }

                // Normalize keys
                $packages[] = [
                    'type'    => $decoded['type']    ?? 'Custom',
                    'status'  => $decoded['status']  ?? 'New',
                    'repo'    => $decoded['repo']    ?? null,
                    'version' => $decoded['version'] ?? null,
                    'comment' => $decoded['comment'] ?? '',
                ];
            }

            flock($fh, LOCK_UN);
        } finally {
            fclose($fh);
        }

        return $packages;
    }

    /**
     * Save all package entries back to the JSONL file.
     *
     * @param array<int,array<string,mixed>> $packages
     */
    public function save(array $packages): void
    {
        $fh = fopen($this->path, 'c+');
        if (!$fh) {
            throw new RuntimeException("Unable to open package directory file for writing: {$this->path}");
        }

        try{
            if (!flock($fh, LOCK_EX)) {
                throw new RuntimeException("Unable to acquire exclusive lock on {$this->path}");
            }

            // Truncate and rewrite
            ftruncate($fh, 0);
            rewind($fh);

            // Header comments
            fwrite($fh, "# HelioNET Dynamic Package Directory\n");
            fwrite($fh, "# JSONL format: one JSON object per line\n");
            fwrite($fh, "# Fields: type, status, repo, version, comment\n");

            foreach ($packages as $pkg) {
                $line = json_encode([
                    'type'    => $pkg['type']    ?? 'Custom',
                    'status'  => $pkg['status']  ?? 'New',
                    'repo'    => $pkg['repo']    ?? null,
                    'version' => $pkg['version'] ?? null,
                    'comment' => $pkg['comment'] ?? '',
                ], JSON_UNESCAPED_SLASHES);

                if ($line !== false) {
                    fwrite($fh, $line . PHP_EOL);
                }
            }

            fflush($fh);
            flock($fh, LOCK_UN);
        } finally {
            fclose($fh);
        }
    }

    private const DEFAULT_PACKAGES = [
        [
            "type"    => "Core",
            "status"  => "New",
            "repo"    => "capsulecmdr/helionet-web",
            "version" => "@dev",
            "comment" => ""
        ],
        // [
        //     "type"    => "Core",
        //     "status"  => "New",
        //     "repo"    => "capsulecmdr/helionet-api",
        //     "version" => "@dev",
        //     "comment" => ""
        // ],
        // [
        //     "type"    => "Base",
        //     "status"  => "New",
        //     "repo"    => "capsulecmdr/helionet-ui",
        //     "version" => "^1.0",
        //     "comment" => "Default UI components"
        // ],
        // [
        //     "type"    => "Community",
        //     "status"  => "New",
        //     "repo"    => "somevendor/helionet-addon",
        //     "version" => "^2.0",
        //     "comment" => "Example addon"
        // ],
        // [
        //     "type"    => "Custom",
        //     "status"  => "Disabled",
        //     "repo"    => "capsulecmdr/custom-alpha",
        //     "version" => "dev-master",
        //     "comment" => "Optional custom extension"
        // ]
    ];

    private function ensureFileExists(): void
    {
        if (!file_exists($this->path)) {
            $dir = dirname($this->path);

            if (!is_dir($dir)) {
                if (!mkdir($dir, 0775, true) && !is_dir($dir)) {
                    throw new RuntimeException("Unable to create directory for package file: {$dir}");
                }
            }

            $fh = fopen($this->path, 'w');
            if (!$fh) {
                throw new RuntimeException("Unable to create package directory file: {$this->path}");
            }

            // Write header
            fwrite($fh, "# HelioNET Dynamic Package Directory\n");
            fwrite($fh, "# JSONL format: one JSON object per line\n");
            fwrite($fh, "# Fields: type, status, repo, version, comment\n\n");

            // Write default packages
            foreach (self::DEFAULT_PACKAGES as $package) {
                fwrite($fh, json_encode($package, JSON_UNESCAPED_SLASHES) . PHP_EOL);
            }

            fclose($fh);
        }
    }

}
