<?php
/**
 * Server Admin Panel
 * 
 * A simple admin panel for managing websites, PHP versions, and server status
 * 
 * IMPORTANT: This file should be placed in a secure location with proper authentication!
 */

session_start();

// Basic security: Very simple login (REPLACE THIS WITH PROPER AUTHENTICATION)
$admin_username = "admin";
$admin_password = "changeme";  // CHANGE THIS IMMEDIATELY

// Check if logged in
$logged_in = false;
if (isset($_SESSION['logged_in']) && $_SESSION['logged_in'] === true) {
    $logged_in = true;
}

// Login handling
if (isset($_POST['login'])) {
    if ($_POST['username'] === $admin_username && $_POST['password'] === $admin_password) {
        $_SESSION['logged_in'] = true;
        $logged_in = true;
    } else {
        $error_message = "Invalid login credentials";
    }
}

// Logout handling
if (isset($_GET['logout'])) {
    session_destroy();
    header("Location: ".$_SERVER['PHP_SELF']);
    exit;
}

// Function to execute shell commands safely
function execute_command($command) {
    $output = null;
    $return_var = null;
    
    // Execute the command
    exec("sudo $command 2>&1", $output, $return_var);
    
    return [
        'success' => $return_var === 0,
        'output' => implode("\n", $output)
    ];
}

// Function to get all websites
function get_websites() {
    $websites = [];
    
    // Get all directories in /sites
    $sites_dir = '/sites';
    if (is_dir($sites_dir)) {
        $dirs = scandir($sites_dir);
        
        foreach ($dirs as $dir) {
            if ($dir !== '.' && $dir !== '..' && is_dir("$sites_dir/$dir")) {
                $php_version = "Unknown";
                
                // Check if PHP version file exists
                if (file_exists("$sites_dir/$dir/php_version.txt")) {
                    $php_version = trim(file_get_contents("$sites_dir/$dir/php_version.txt"));
                } else {
                    // Try to extract PHP version from Nginx config
                    $nginx_config = "/etc/nginx/sites-available/$dir.conf";
                    if (file_exists($nginx_config)) {
                        $content = file_get_contents($nginx_config);
                        if (preg_match('/php([0-9]\.[0-9])-fpm\.sock/', $content, $matches)) {
                            $php_version = $matches[1];
                        }
                    }
                }
                
                $websites[] = [
                    'domain' => $dir,
                    'php_version' => $php_version,
                    'public_html' => "$sites_dir/$dir/public_html",
                    'logs_dir' => "$sites_dir/$dir/logs"
                ];
            }
        }
    }
    
    return $websites;
}

// Function to get system information
function get_system_info() {
    $system_info = [];
    
    // Get CPU info
    $cpu_info = shell_exec("cat /proc/cpuinfo | grep 'model name' | head -1");
    $system_info['cpu'] = trim(explode(":", $cpu_info)[1] ?? "Unknown");
    
    // Get memory info
    $mem_info = shell_exec("free -m | grep 'Mem:'");
    $mem_parts = preg_split('/\s+/', trim($mem_info));
    $system_info['memory_total'] = $mem_parts[1] ?? "Unknown";
    $system_info['memory_used'] = $mem_parts[2] ?? "Unknown";
    $system_info['memory_free'] = $mem_parts[3] ?? "Unknown";
    
    // Get disk info
    $disk_info = shell_exec("df -h / | tail -1");
    $disk_parts = preg_split('/\s+/', trim($disk_info));
    $system_info['disk_total'] = $disk_parts[1] ?? "Unknown";
    $system_info['disk_used'] = $disk_parts[2] ?? "Unknown";
    $system_info['disk_free'] = $disk_parts[3] ?? "Unknown";
    
    // Get uptime
    $uptime = shell_exec("uptime -p");
    $system_info['uptime'] = trim($uptime ?? "Unknown");
    
    // Get load average
    $load = shell_exec("uptime");
    if (preg_match('/load average: (.*)/', $load, $matches)) {
        $system_info['load'] = trim($matches[1]);
    } else {
        $system_info['load'] = "Unknown";
    }
    
    return $system_info;
}

// Function to get PHP versions
function get_php_versions() {
    $php_versions = [];
    $versions = ['7.4', '8.0', '8.1', '8.2'];
    
    foreach ($versions as $version) {
        $status = file_exists("/usr/sbin/php-fpm$version") ? "Installed" : "Not Installed";
        $php_versions[] = [
            'version' => $version,
            'status' => $status
        ];
    }
    
    return $php_versions;
}

// Function to get service status
function get_service_status($service) {
    $output = shell_exec("systemctl is-active $service 2>&1");
    return trim($output) === 'active' ? 'Running' : 'Stopped';
}

// Function to get server services
function get_services() {
    $services = [
        [
            'name' => 'Nginx',
            'service' => 'nginx',
            'status' => get_service_status('nginx'),
        ],
        [
            'name' => 'Apache',
            'service' => 'apache2',
            'status' => get_service_status('apache2'),
        ],
        [
            'name' => 'MySQL',
            'service' => 'mysql',
            'status' => get_service_status('mysql'),
        ],
        [
            'name' => 'PHP-FPM 7.4',
            'service' => 'php7.4-fpm',
            'status' => get_service_status('php7.4-fpm'),
        ],
        [
            'name' => 'PHP-FPM 8.0',
            'service' => 'php8.0-fpm',
            'status' => get_service_status('php8.0-fpm'),
        ],
        [
            'name' => 'PHP-FPM 8.1',
            'service' => 'php8.1-fpm',
            'status' => get_service_status('php8.1-fpm'),
        ],
        [
            'name' => 'PHP-FPM 8.2',
            'service' => 'php8.2-fpm',
            'status' => get_service_status('php8.2-fpm'),
        ],
        [
            'name' => 'Fail2Ban',
            'service' => 'fail2ban',
            'status' => get_service_status('fail2ban'),
        ]
    ];
    
    return $services;
}

// Handle actions
$action_result = null;
if ($logged_in && isset($_POST['action'])) {
    switch ($_POST['action']) {
        case 'add_website':
            if (!empty($_POST['domain']) && !empty($_POST['php_version'])) {
                $domain = escapeshellarg($_POST['domain']);
                $php_version = escapeshellarg($_POST['php_version']);
                $action_result = execute_command("/usr/bin/bash /path/to/site_config.sh $domain $php_version");
            } else {
                $action_result = ['success' => false, 'output' => 'Domain and PHP version are required'];
            }
            break;
            
        case 'switch_php':
            if (!empty($_POST['domain']) && !empty($_POST['php_version'])) {
                $domain = escapeshellarg($_POST['domain']);
                $php_version = escapeshellarg($_POST['php_version']);
                $action_result = execute_command("/usr/bin/bash /path/to/php_switcher.sh $domain $php_version");
            } else {
                $action_result = ['success' => false, 'output' => 'Domain and PHP version are required'];
            }
            break;
            
        case 'remove_website':
            if (!empty($_POST['domain'])) {
                $domain = escapeshellarg($_POST['domain']);
                
                // Remove Nginx config
                execute_command("rm -f /etc/nginx/sites-enabled/$domain.conf");
                execute_command("rm -f /etc/nginx/sites-available/$domain.conf");
                
                // Remove Apache config
                execute_command("a2dissite $domain.conf");
                execute_command("rm -f /etc/apache2/sites-available/$domain.conf");
                
                // Remove website files (optional)
                if (isset($_POST['remove_files']) && $_POST['remove_files'] === 'yes') {
                    $result = execute_command("rm -rf /sites/$domain");
                    $action_result = $result;
                } else {
                    $action_result = ['success' => true, 'output' => "Website $domain configurations removed. Website files were NOT deleted."];
                }
                
                // Reload web servers
                execute_command("systemctl reload nginx");
                execute_command("systemctl reload apache2");
            } else {
                $action_result = ['success' => false, 'output' => 'Domain is required'];
            }
            break;
            
        case 'restart_service':
            if (!empty($_POST['service'])) {
                $service = escapeshellarg($_POST['service']);
                $action_result = execute_command("systemctl restart $service");
            } else {
                $action_result = ['success' => false, 'output' => 'Service name is required'];
            }
            break;
            
        case 'backup_website':
            if (!empty($_POST['domain'])) {
                $domain = escapeshellarg($_POST['domain']);
                $backup_dir = "/sites/$domain/backup";
                $timestamp = date('Y-m-d_H-i-s');
                $backup_file = "$backup_dir/$domain-$timestamp.tar.gz";
                
                // Create backup directory if it doesn't exist
                execute_command("mkdir -p $backup_dir");
                
                // Create backup
                $result = execute_command("tar -czf $backup_file -C /sites/$domain public_html");
                
                if ($result['success']) {
                    $action_result = ['success' => true, 'output' => "Backup created: $backup_file"];
                } else {
                    $action_result = $result;
                }
            } else {
                $action_result = ['success' => false, 'output' => 'Domain is required'];
            }
            break;
            
        case 'view_logs':
            if (!empty($_POST['domain']) && !empty($_POST['log_type'])) {
                $domain = $_POST['domain']; // Not escaping because used in PHP
                $log_type = $_POST['log_type'];
                
                // Define log file paths
                $log_file = '';
                switch ($log_type) {
                    case 'nginx_access':
                        $log_file = "/sites/$domain/logs/access.log";
                        break;
                    case 'nginx_error':
                        $log_file = "/sites/$domain/logs/error.log";
                        break;
                    case 'apache_access':
                        $log_file = "/sites/$domain/logs/apache-access.log";
                        break;
                    case 'apache_error':
                        $log_file = "/sites/$domain/logs/apache-error.log";
                        break;
                }
                
                // Read log file (last 100 lines)
                if (!empty($log_file) && file_exists($log_file)) {
                    $log_content = shell_exec("tail -n 100 $log_file");
                    $action_result = ['success' => true, 'output' => $log_content];
                } else {
                    $action_result = ['success' => false, 'output' => "Log file $log_file does not exist"];
                }
            } else {
                $action_result = ['success' => false, 'output' => 'Domain and log type are required'];
            }
            break;
    }
}

// Get data for display
$websites = $logged_in ? get_websites() : [];
$system_info = $logged_in ? get_system_info() : [];
$services = $logged_in ? get_services() : [];
$php_versions = $logged_in ? get_php_versions() : [];

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Server Admin Panel</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .card { background: white; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.12); padding: 20px; margin-bottom: 20px; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
        .tabs { display: flex; margin-bottom: 20px; }
        .tab { padding: 10px 15px; cursor: pointer; border-bottom: 2px solid transparent; }
        .tab.active { border-bottom: 2px solid #007bff; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        table { width: 100%; border-collapse: collapse; }
        table th, table td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        form { margin-bottom: 20px; }
        input, select { padding: 8px; width: 100%; margin-bottom: 10px; box-sizing: border-box; }
        button { padding: 8px 15px; background: #007bff; color: white; border: none; cursor: pointer; }
        .alert { padding: 15px; margin-bottom: 20px; border-radius: 4px; }
        .alert-success { background-color: #d4edda; color: #155724; }
        .alert-danger { background-color: #f8d7da; color: #721c24; }
        .status-running { color: green; }
        .status-stopped { color: red; }
        .actions { display: flex; gap: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Server Admin Panel</h1>
            <?php if ($logged_in): ?>
                <a href="?logout=1">Logout</a>
            <?php endif; ?>
        </div>
        
        <?php if (!$logged_in): ?>
            <div class="card">
                <h2>Login</h2>
                <?php if (isset($error_message)): ?>
                    <div class="alert alert-danger"><?php echo $error_message; ?></div>
                <?php endif; ?>
                <form method="post">
                    <div>
                        <label for="username">Username</label>
                        <input type="text" id="username" name="username" required>
                    </div>
                    <div>
                        <label for="password">Password</label>
                        <input type="password" id="password" name="password" required>
                    </div>
                    <button type="submit" name="login">Login</button>
                </form>
            </div>
        <?php else: ?>
            <?php if ($action_result): ?>
                <div class="alert <?php echo $action_result['success'] ? 'alert-success' : 'alert-danger'; ?>">
                    <pre><?php echo htmlspecialchars($action_result['output']); ?></pre>
                </div>
            <?php endif; ?>
            
            <div class="tabs">
                <div class="tab active" data-tab="websites">Websites</div>
                <div class="tab" data-tab="system">System</div>
                <div class="tab" data-tab="services">Services</div>
                <div class="tab" data-tab="add-website">Add Website</div>
            </div>
            
            <div id="websites" class="tab-content active">
                <div class="card">
                    <h2>Manage Websites</h2>
                    <table>
                        <thead>
                            <tr>
                                <th>Domain</th>
                                <th>PHP Version</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (empty($websites)): ?>
                                <tr>
                                    <td colspan="3">No websites found</td>
                                </tr>
                            <?php else: ?>
                                <?php foreach ($websites as $website): ?>
                                    <tr>
                                        <td><?php echo htmlspecialchars($website['domain']); ?></td>
                                        <td><?php echo htmlspecialchars($website['php_version']); ?></td>
                                        <td class="actions">
                                            <form method="post" style="display: inline;">
                                                <input type="hidden" name="action" value="switch_php">
                                                <input type="hidden" name="domain" value="<?php echo htmlspecialchars($website['domain']); ?>">
                                                <select name="php_version" style="width: auto;">
                                                    <option value="7.4" <?php echo $website['php_version'] === '7.4' ? 'selected' : ''; ?>>PHP 7.4</option>
                                                    <option value="8.0" <?php echo $website['php_version'] === '8.0' ? 'selected' : ''; ?>>PHP 8.0</option>
                                                    <option value="8.1" <?php echo $website['php_version'] === '8.1' ? 'selected' : ''; ?>>PHP 8.1</option>
                                                    <option value="8.2" <?php echo $website['php_version'] === '8.2' ? 'selected' : ''; ?>>PHP 8.2</option>
                                                </select>
                                                <button type="submit">Switch PHP</button>
                                            </form>
                                            
                                            <form method="post" style="display: inline;">
                                                <input type="hidden" name="action" value="backup_website">
                                                <input type="hidden" name="domain" value="<?php echo htmlspecialchars($website['domain']); ?>">
                                                <button type="submit">Backup</button>
                                            </form>
                                            
                                            <form method="post" style="display: inline;" onsubmit="return confirm('Are you sure you want to view logs?');">
                                                <input type="hidden" name="action" value="view_logs">
                                                <input type="hidden" name="domain" value="<?php echo htmlspecialchars($website['domain']); ?>">
                                                <select name="log_type" style="width: auto;">
                                                    <option value="nginx_access">Nginx Access</option>
                                                    <option value="nginx_error">Nginx Error</option>
                                                    <option value="apache_access">Apache Access</option>
                                                    <option value="apache_error">Apache Error</option>
                                                </select>
                                                <button type="submit">View Logs</button>
                                            </form>
                                            
                                            <form method="post" style="display: inline;" onsubmit="return confirm('Are you sure you want to remove this website?');">
                                                <input type="hidden" name="action" value="remove_website">
                                                <input type="hidden" name="domain" value="<?php echo htmlspecialchars($website['domain']); ?>">
                                                <label>
                                                    <input type="checkbox" name="remove_files" value="yes"> Remove files
                                                </label>
                                                <button type="submit">Remove</button>
                                            </form>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div id="system" class="tab-content">
                <div class="card">
                    <h2>System Information</h2>
                    <table>
                        <tr>
                            <th>CPU</th>
                            <td><?php echo htmlspecialchars($system_info['cpu']); ?></td>
                        </tr>
                        <tr>
                            <th>Memory</th>
                            <td>
                                Total: <?php echo htmlspecialchars($system_info['memory_total']); ?> MB
                                Used: <?php echo htmlspecialchars($system_info['memory_used']); ?> MB
                                Free: <?php echo htmlspecialchars($system_info['memory_free']); ?> MB
                            </td>
                        </tr>
                        <tr>
                            <th>Disk</th>
                            <td>
                                Total: <?php echo htmlspecialchars($system_info['disk_total']); ?>
                                Used: <?php echo htmlspecialchars($system_info['disk_used']); ?>
                                Free: <?php echo htmlspecialchars($system_info['disk_free']); ?>
                            </td>
                        </tr>
                        <tr>
                            <th>Uptime</th>
                            <td><?php echo htmlspecialchars($system_info['uptime']); ?></td>
                        </tr>
                        <tr>
                            <th>Load Average</th>
                            <td><?php echo htmlspecialchars($system_info['load']); ?></td>
                        </tr>
                    </table>
                </div>
                
                <div class="card">
                    <h2>PHP Versions</h2>
                    <table>
                        <thead>
                            <tr>
                                <th>Version</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($php_versions as $php_version): ?>
                                <tr>
                                    <td>PHP <?php echo htmlspecialchars($php_version['version']); ?></td>
                                    <td><?php echo htmlspecialchars($php_version['status']); ?></td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div id="services" class="tab-content">
                <div class="card">
                    <h2>Services</h2>
                    <table>
                        <thead>
                            <tr>
                                <th>Service</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($services as $service): ?>
                                <tr>
                                    <td><?php echo htmlspecialchars($service['name']); ?></td>
                                    <td class="status-<?php echo strtolower($service['status']); ?>">
                                        <?php echo htmlspecialchars($service['status']); ?>
                                    </td>
                                    <td>
                                        <form method="post">
                                            <input type="hidden" name="action" value="restart_service">
                                            <input type="hidden" name="service" value="<?php echo htmlspecialchars($service['service']); ?>">
                                            <button type="submit">Restart</button>
                                        </form>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div id="add-website" class="tab-content">
                <div class="card">
                    <h2>Add New Website</h2>
                    <form method="post">
                        <input type="hidden" name="action" value="add_website">
                        <div>
                            <label for="domain">Domain Name</label>
                            <input type="text" id="domain" name="domain" required placeholder="example.com">
                        </div>
                        <div>
                            <label for="php_version">PHP Version</label>
                            <select id="php_version" name="php_version" required>
                                <option value="7.4">PHP 7.4</option>
                                <option value="8.0" selected>PHP 8.0</option>
                                <option value="8.1">PHP 8.1</option>
                                <option value="8.2">PHP 8.2</option>
                            </select>
                        </div>
                        <button type="submit">Add Website</button>
                    </form>
                </div>
            </div>
        <?php endif; ?>
    </div>
    
    <script>
        // Tab functionality
        document.addEventListener('DOMContentLoaded', function() {
            const tabs = document.querySelectorAll('.tab');
            
            tabs.forEach(tab => {
                tab.addEventListener('click', function() {
                    // Remove active class from all tabs and tab contents
                    tabs.forEach(t => t.classList.remove('active'));
                    document.querySelectorAll('.tab-content').forEach(content => {
                        content.classList.remove('active');
                    });
                    
                    // Add active class to clicked tab and corresponding content
                    this.classList.add('active');
                    const tabId = this.getAttribute('data-tab');
                    document.getElementById(tabId).classList.add('active');
                });
            });
        });
    </script>
</body>
</html>
