<?php
require_once 'config.php';
require_once 'includes/database.php';
require_once 'includes/functions.php';
require_once 'jdf.php';

// Start the session if not already started
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// Check if user is logged in
if (!isset($_SESSION['auth_code'])) {
    header('Location: index.php');
    exit;
}

$auth_code = $_SESSION['auth_code'];
$user = get_user_by_auth($auth_code);
if (!$user) {
    session_destroy();
    header('Location: index.php');
    exit;
}

$conn = connect_main_db();

// Handle speed server selection
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'select_speed_server') {
    $speed_server_id = isset($_POST['speed_server_id']) ? (int)$_POST['speed_server_id'] : null;
    
    // Check if user has a smart subscription
    $stmt = $conn->prepare("SELECT id FROM fl_all_configs_subscription WHERE userid = ?");
    $stmt->bind_param("s", $user['userid']);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        $all_configs_sub = $result->fetch_assoc();
        $now = time();
        
        // Update speed server selection and record admin usage data
        $stmt = $conn->prepare("UPDATE fl_all_configs_subscription SET speed_server_id = ?, updated_at = ? WHERE id = ?");
        $stmt->bind_param("iii", $speed_server_id, $now, $all_configs_sub['id']);
        
        if ($stmt->execute()) {
            // Update speed server statistics for admin tracking
            if ($speed_server_id) {
                $stmt = $conn->prepare("UPDATE fl_speed_servers SET last_test_time = ?, test_count = test_count + 1, updated_at = ? WHERE id = ?");
                $stmt->bind_param("iii", $now, $now, $speed_server_id);
                $stmt->execute();
                $_SESSION['message'] = 'سرور سرعت با موفقیت انتخاب شد.';
            } else {
                $_SESSION['message'] = 'انتخاب سرور سرعت با موفقیت حذف شد.';
            }
        } else {
            $_SESSION['error'] = 'خطا در تغییر تنظیمات سرور سرعت.';
        }
    } else {
        $_SESSION['error'] = 'برای استفاده از این قابلیت، ابتدا باید اشتراک هوشمند ایجاد کنید.';
    }
    
    header('Location: server_settings.php');
    exit;
}

// Handle smart subscription creation
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'create_smart_sub') {
    $all_configs_sub = get_or_create_all_configs_subscription($user['userid']);
    $_SESSION['message'] = 'اشتراک هوشمند با موفقیت ایجاد شد.';
    header('Location: server_settings.php');
    exit;
}

// Get messages from session and clear them
$message = '';
$error = '';
if (isset($_SESSION['message'])) {
    $message = $_SESSION['message'];
    unset($_SESSION['message']);
}
if (isset($_SESSION['error'])) {
    $error = $_SESSION['error'];
    unset($_SESSION['error']);
}

// Get user's current speed server preference
$current_speed_server_id = null;
$all_configs_sub = null;
$has_smart_sub = false;
$stmt = $conn->prepare("SELECT id, speed_server_id FROM fl_all_configs_subscription WHERE userid = ?");
$stmt->bind_param("s", $user['userid']);
$stmt->execute();
$result = $stmt->get_result();
$all_configs_sub = $result->fetch_assoc();

if ($all_configs_sub) {
    $has_smart_sub = true;
    $current_speed_server_id = $all_configs_sub['speed_server_id'];
}

// Get all active speed servers
$speed_servers = [];
$stmt = $conn->prepare("SELECT * FROM fl_speed_servers WHERE active = 1 ORDER BY name");
$stmt->execute();
$result = $stmt->get_result();
while ($server = $result->fetch_assoc()) {
    $speed_servers[] = $server;
}

// Get user's main servers (for context)
$user_servers = [];
$orders = get_user_orders($user['userid']);
foreach ($orders as $order) {
    if (!isset($user_servers[$order['server_id']])) {
        $user_servers[$order['server_id']] = $order['server_name'];
    }
}
?>

<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تنظیم سرور - تست سرعت پیشرفته</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <style>
        @font-face {
            font-family: 'Vazirmatn';
            src: url('https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/fonts/webfonts/Vazirmatn-Regular.woff2') format('woff2');
            font-weight: normal;
            font-style: normal;
            font-display: swap;
        }
        
        body {
            font-family: 'Vazirmatn', Tahoma, sans-serif;
            background-color: #f5f7fa;
            padding-bottom: 70px;
        }

        .header-card {
            border-radius: 16px 16px 0 0;
            background: linear-gradient(135deg, #f97316 0%, #fb923c 100%);
            position: relative;
            overflow: hidden;
        }

        .speed-card {
            transition: all 0.3s ease;
            border-radius: 16px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05);
            border: 1px solid rgba(229, 231, 235, 0.7);
            overflow: hidden;
        }
        
        .speed-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.1);
        }

        .speed-card.selected {
            border-color: #f97316;
            background-color: #fef3f2;
            box-shadow: 0 0 0 3px rgba(249, 115, 22, 0.1);
        }

        .clock {
            font-size: 3rem;
            font-weight: 800;
            color: white;
            text-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }

        .speed-badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 9999px;
            font-size: 0.875rem;
            font-weight: 500;
        }
        
        .speed-badge.excellent {
            background-color: #dcfce7;
            color: #16a34a;
        }
        
        .speed-badge.good {
            background-color: #dbeafe;
            color: #2563eb;
        }
        
        .speed-badge.average {
            background-color: #fef3c7;
            color: #d97706;
        }
        
        .speed-badge.poor {
            background-color: #fee2e2;
            color: #dc2626;
        }
        
        .speed-badge.unknown {
            background-color: #f3f4f6;
            color: #6b7280;
        }

        .test-metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 0.5rem;
            margin-top: 0.5rem;
        }

        .metric-item {
            background: #f8fafc;
            padding: 0.5rem;
            border-radius: 0.5rem;
            text-align: center;
            font-size: 0.75rem;
        }

        .metric-value {
            font-weight: 600;
            color: #1f2937;
        }

        .metric-label {
            color: #6b7280;
            font-size: 0.625rem;
        }

        .progress-ring {
            transform: rotate(-90deg);
        }

        .progress-ring-circle {
            stroke-dasharray: 251.2;
            stroke-dashoffset: 251.2;
            transition: stroke-dashoffset 0.5s ease-in-out;
        }
    </style>
</head>
<body>
    <div class="min-h-screen">
        <div class="container mx-auto px-4 py-8">
            <!-- Header Card -->
            <div class="header-card p-6 mb-8">
                <div class="flex flex-col md:flex-row items-center justify-between relative z-10">
                    <div class="text-center md:text-right">
                        <h1 class="text-3xl font-black text-white">تست سرعت پیشرفته</h1>
                        <p class="text-white text-opacity-90 mt-2">انتخاب سرور بهینه با تست جامع</p>
                        
                        <div class="mt-4">
                            <a href="hub.php" class="inline-flex items-center px-4 py-2 bg-white bg-opacity-20 text-white rounded-lg hover:bg-opacity-30 transition duration-200">
                                <i class="fas fa-arrow-right ml-2"></i>
                                بازگشت به داشبورد
                            </a>
                        </div>
                    </div>
                    
                    <div class="mt-6 md:mt-0 flex flex-col items-center md:items-end">
                        <div id="current-time" class="clock mb-2"></div>
                        <p class="text-sm text-white opacity-90 font-medium"><?= jdate('l، d F Y', time(), '', '', 'fa') ?></p>
                    </div>
                </div>
            </div>

            <!-- Messages -->
            <?php if ($message): ?>
            <div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-6">
                <i class="fas fa-check-circle ml-2"></i><?= htmlspecialchars($message) ?>
            </div>
            <?php endif; ?>
            
            <?php if ($error): ?>
            <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-6">
                <i class="fas fa-exclamation-circle ml-2"></i><?= htmlspecialchars($error) ?>
            </div>
            <?php endif; ?>

            <!-- Speed Servers Section -->
            <div class="bg-white rounded-lg shadow-sm p-6">
                <div class="flex items-center justify-between mb-6">
                    <div>
                        <h2 class="text-2xl font-bold text-gray-800">تست سرعت و کیفیت اتصال</h2>
                        <p class="text-gray-600 mt-1">تست جامع سرعت، پینگ و کیفیت اتصال</p>
                    </div>
                    
                    <?php if ($has_smart_sub): ?>
                    <div class="flex space-x-2">
                        <button onclick="testAllServers()" 
                                class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg transition duration-200">
                            <i class="fas fa-sync-alt ml-2"></i>
                            تست همه سرورها
                        </button>
                        <button onclick="benchmarkAllServers()" 
                                class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded-lg transition duration-200">
                            <i class="fas fa-chart-line ml-2"></i>
                            تست عملکرد کامل
                        </button>
                    </div>
                    <?php endif; ?>
                </div>

                <?php if (!$has_smart_sub): ?>
                <!-- Smart Subscription Required Message -->
                <div class="text-center py-12">
                    <div class="text-6xl text-orange-200 mb-4">
                        <i class="fas fa-exclamation-triangle"></i>
                    </div>
                    <h3 class="text-xl font-bold text-gray-600 mb-2">اشتراک هوشمند مورد نیاز است</h3>
                    <p class="text-gray-500 mb-6">برای استفاده از تست سرعت پیشرفته، ابتدا باید اشتراک هوشمند ایجاد کنید.</p>
                    
                    <div class="max-w-md mx-auto bg-gradient-to-r from-indigo-500 to-purple-600 rounded-lg p-6 text-white">
                        <div class="flex items-center justify-center mb-4">
                            <div class="w-16 h-16 bg-white bg-opacity-20 rounded-full flex items-center justify-center">
                                <i class="fas fa-magic text-2xl"></i>
                            </div>
                        </div>
                        <h3 class="text-xl font-bold mb-2">اشتراک هوشمند</h3>
                        <p class="text-white text-opacity-90 mb-4 text-sm">
                            دسترسی به تست سرعت پیشرفته + انتخاب سرور بهینه + تست کیفیت اتصال
                        </p>
                        <form method="POST" action="">
                            <input type="hidden" name="action" value="create_smart_sub">
                            <button type="submit" class="w-full bg-white bg-opacity-20 hover:bg-opacity-30 text-white px-4 py-2 rounded-lg transition duration-200">
                                <i class="fas fa-plus ml-2"></i>
                                ایجاد اشتراک هوشمند
                            </button>
                        </form>
                    </div>
                </div>
                <?php elseif (empty($speed_servers)): ?>
                <div class="text-center py-12">
                    <div class="text-6xl text-gray-200 mb-4">
                        <i class="fas fa-server"></i>
                    </div>
                    <h3 class="text-xl font-bold text-gray-600 mb-2">سرور سرعتی تعریف نشده</h3>
                    <p class="text-gray-500">هیچ سرور سرعتی برای تست در دسترس نیست.</p>
                </div>
                <?php else: ?>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6" id="speedServersList">
                    <?php foreach ($speed_servers as $server): ?>
                    <div class="speed-card <?= $current_speed_server_id == $server['id'] ? 'selected' : '' ?>" 
                         data-server-id="<?= $server['id'] ?>" 
                         data-server-domain="<?= htmlspecialchars($server['speed_domain']) ?>"
                         data-server-port="<?= $server['test_port'] ?>">
                        <div class="p-4">
                            <!-- Server Header -->
                            <div class="flex items-center justify-between mb-3">
                                <div class="flex items-center">
                                    <div class="w-12 h-12 bg-orange-100 text-orange-600 rounded-full flex items-center justify-center ml-3">
                                        <i class="fas fa-server text-lg"></i>
                                    </div>
                                    <div>
                                        <h3 class="text-lg font-bold text-gray-800"><?= htmlspecialchars($server['name']) ?></h3>
                                        <p class="text-sm text-gray-600"><?= htmlspecialchars($server['speed_domain']) ?></p>
                                    </div>
                                </div>
                                
                                <?php if ($current_speed_server_id == $server['id']): ?>
                                <div class="bg-green-100 text-green-800 px-2 py-1 rounded-full text-xs font-medium">
                                    <i class="fas fa-check ml-1"></i>انتخاب شده
                                </div>
                                <?php endif; ?>
                            </div>

                            <!-- Test Progress -->
                            <div class="mb-3">
                                <div class="flex items-center justify-between text-sm mb-1">
                                    <span class="text-gray-500">وضعیت تست:</span>
                                    <div id="test-status-<?= $server['id'] ?>" class="text-gray-600">
                                        <i class="fas fa-clock ml-1"></i>
                                        آماده تست
                                    </div>
                                </div>
                                <div id="test-progress-<?= $server['id'] ?>" class="w-full bg-gray-200 rounded-full h-2 hidden">
                                    <div class="bg-blue-600 h-2 rounded-full transition-all duration-300" style="width: 0%"></div>
                                </div>
                            </div>

                            <!-- Test Metrics -->
                            <div id="test-metrics-<?= $server['id'] ?>" class="test-metrics hidden">
                                <div class="metric-item">
                                    <div class="metric-value" id="ping-<?= $server['id'] ?>">-</div>
                                    <div class="metric-label">پینگ (ms)</div>
                                </div>
                                <div class="metric-item">
                                    <div class="metric-value" id="download-<?= $server['id'] ?>">-</div>
                                    <div class="metric-label">دانلود (KB/s)</div>
                                </div>
                                <div class="metric-item">
                                    <div class="metric-value" id="upload-<?= $server['id'] ?>">-</div>
                                    <div class="metric-label">آپلود (KB/s)</div>
                                </div>
                                <div class="metric-item">
                                    <div class="metric-value" id="loss-<?= $server['id'] ?>">-</div>
                                    <div class="metric-label">از دست رفتن (%)</div>
                                </div>
                            </div>

                            <!-- Action Buttons -->
                            <div class="space-y-2 mt-4">
                                <button onclick="runComprehensiveTest(<?= $server['id'] ?>, '<?= htmlspecialchars($server['speed_domain']) ?>', <?= $server['test_port'] ?>)" 
                                        class="w-full bg-blue-600 hover:bg-blue-700 text-white px-3 py-2 rounded-lg text-sm font-medium transition duration-200">
                                    <i class="fas fa-play ml-2"></i>
                                    تست کامل
                                </button>
                                
                                <?php if ($current_speed_server_id != $server['id']): ?>
                                <button onclick="selectSpeedServer(<?= $server['id'] ?>, '<?= htmlspecialchars($server['name']) ?>', this)" 
                                        class="w-full bg-orange-600 hover:bg-orange-700 text-white px-3 py-2 rounded-lg text-sm font-medium transition duration-200">
                                    <i class="fas fa-check ml-2"></i>
                                    انتخاب این سرور
                                </button>
                                <?php else: ?>
                                <button onclick="selectSpeedServer(null, 'حذف انتخاب', this)" 
                                        class="w-full bg-gray-600 hover:bg-gray-700 text-white px-3 py-2 rounded-lg text-sm font-medium transition duration-200">
                                    <i class="fas fa-times ml-2"></i>
                                    حذف انتخاب
                                </button>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                    <?php endforeach; ?>
                </div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <?php include 'includes/footer.php'; ?>

    <script>
        // Enhanced speed testing with comprehensive metrics
        const DEBUG_MODE = false;
        const testResults = new Map();
        const activeTests = new Set();
        
        function debugLog(message) {
            if (DEBUG_MODE) {
                console.log(`[Advanced Speed Test] ${message}`);
            }
        }
        
        // Update clock
        function updateClock() {
            const now = new Date();
            const timeString = now.toLocaleTimeString('fa-IR');
            document.getElementById('current-time').textContent = timeString;
        }
        
        updateClock();
        setInterval(updateClock, 1000);

        // Test all servers on page load
        document.addEventListener('DOMContentLoaded', function() {
            <?php if ($has_smart_sub): ?>
            setTimeout(() => {
                testAllServers();
            }, 1000);
            <?php endif; ?>
        });
        
        // Run comprehensive test on a single server
        async function runComprehensiveTest(serverId, domain, port) {
            if (activeTests.has(serverId)) {
                showNotification('تست در حال اجرا است، لطفاً صبر کنید.', 'warning');
                return;
            }
            
            activeTests.add(serverId);
            updateTestStatus(serverId, 'در حال تست...', 'testing');
            showTestProgress(serverId, true);
            
            try {
                const results = {
                    ping: await testPing(domain, serverId),
                    download: await testDownloadSpeed(domain, port, serverId),
                    upload: await testUploadSpeed(domain, port, serverId),
                    dataLoss: await testDataIntegrity(domain, port, serverId)
                };
                
                testResults.set(serverId, results);
                displayTestResults(serverId, results);
                updateTestStatus(serverId, 'تست کامل شد', 'completed');
                
            } catch (error) {
                debugLog(`Comprehensive test failed for server ${serverId}: ${error.message}`);
                updateTestStatus(serverId, 'خطا در تست', 'error');
                showNotification(`خطا در تست سرور: ${error.message}`, 'error');
            } finally {
                activeTests.delete(serverId);
                showTestProgress(serverId, false);
            }
        }
        
        // Test ping with multiple attempts
        async function testPing(domain, serverId) {
            const attempts = 5;
            const pings = [];
            
            for (let i = 0; i < attempts; i++) {
                try {
                    const start = performance.now();
                    const response = await fetch(`https://${domain}:2020/ping`, {
                        method: 'GET',
                        headers: { 
                            'Content-Type': 'application/json',
                            'Origin': 'https://zignalshop.ir'
                        }
                    });
                    
                    if (response.ok) {
                        const end = performance.now();
                        pings.push(end - start);
                    }
                } catch (error) {
                    debugLog(`Ping attempt ${i + 1} failed: ${error.message}`);
                }
                
                updateProgress(serverId, ((i + 1) / attempts) * 25); // 25% of total progress
            }
            
            if (pings.length === 0) throw new Error('All ping attempts failed');
            
            const avgPing = pings.reduce((a, b) => a + b, 0) / pings.length;
            return Math.round(avgPing);
        }
        
        // Test download speed with data integrity check
        async function testDownloadSpeed(domain, port, serverId) {
            const testSizes = [1024 * 1024, 2 * 1024 * 1024]; // 1MB, 2MB
            const speeds = [];
            
            for (let i = 0; i < testSizes.length; i++) {
                try {
                    const size = testSizes[i];
                    const start = performance.now();
                    
                    const response = await fetch(`https://${domain}:${port}/test?size=${size}&hash=true&type=pattern`, {
                        method: 'GET',
                        headers: { 
                            'Origin': 'https://zignalshop.ir'
                        }
                    });
                    
                    if (!response.ok) throw new Error(`HTTP ${response.status}`);
                    
                    const data = await response.arrayBuffer();
                    const end = performance.now();
                    
                    const duration = (end - start) / 1000; // seconds
                    const speed = (data.byteLength / 1024) / duration; // KB/s
                    speeds.push(speed);
                    
                    updateProgress(serverId, 25 + ((i + 1) / testSizes.length) * 25); // 25-50% of total progress
                    
                } catch (error) {
                    debugLog(`Download test ${i + 1} failed: ${error.message}`);
                }
            }
            
            if (speeds.length === 0) throw new Error('All download tests failed');
            
            const avgSpeed = speeds.reduce((a, b) => a + b, 0) / speeds.length;
            return Math.round(avgSpeed);
        }
        
        // Test upload speed
        async function testUploadSpeed(domain, port, serverId) {
            const testSizes = [512 * 1024, 1024 * 1024]; // 512KB, 1MB
            const speeds = [];
            
            for (let i = 0; i < testSizes.length; i++) {
                try {
                    const size = testSizes[i];
                    const testData = generateTestData(size);
                    
                    const start = performance.now();
                    
                    const response = await fetch(`https://${domain}:${port}/`, {
                        method: 'POST',
                        headers: { 
                            'Content-Type': 'application/json',
                            'Origin': 'https://zignalshop.ir'
                        },
                        body: JSON.stringify({
                            type: 'upload',
                            data: testData
                        })
                    });
                    
                    if (!response.ok) throw new Error(`HTTP ${response.status}`);
                    
                    const result = await response.json();
                    const end = performance.now();
                    
                    const duration = (end - start) / 1000; // seconds
                    const speed = (result.received_bytes / 1024) / duration; // KB/s
                    speeds.push(speed);
                    
                    updateProgress(serverId, 50 + ((i + 1) / testSizes.length) * 25); // 50-75% of total progress
                    
                } catch (error) {
                    debugLog(`Upload test ${i + 1} failed: ${error.message}`);
                }
            }
            
            if (speeds.length === 0) throw new Error('All upload tests failed');
            
            const avgSpeed = speeds.reduce((a, b) => a + b, 0) / speeds.length;
            return Math.round(avgSpeed);
        }
        
        // Test data integrity and loss
        async function testDataIntegrity(domain, port, serverId) {
            const testData = generateTestData(1024 * 100); // 100KB test
            const expectedHash = await calculateHash(testData);
            
            try {
                const response = await fetch(`https://${domain}:${port}/`, {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Origin': 'https://zignalshop.ir'
                    },
                    body: JSON.stringify({
                        type: 'data_integrity',
                        data: testData,
                        hash: expectedHash
                    })
                });
                
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                
                const result = await response.json();
                updateProgress(serverId, 100); // 100% of total progress
                
                return result.data_integrity ? 0 : 100; // 0% loss if integrity check passes
                
            } catch (error) {
                debugLog(`Data integrity test failed: ${error.message}`);
                return 100; // 100% loss on error
            }
        }
        
        // Generate test data
        function generateTestData(size) {
            const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
            let result = '';
            for (let i = 0; i < size; i++) {
                result += chars.charAt(Math.floor(Math.random() * chars.length));
            }
            return result;
        }
        
        // Calculate SHA-256 hash
        async function calculateHash(data) {
            const encoder = new TextEncoder();
            const dataBuffer = encoder.encode(data);
            const hashBuffer = await crypto.subtle.digest('SHA-256', dataBuffer);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        }
        
        // Update test status
        function updateTestStatus(serverId, status, type = 'info') {
            const statusElement = document.getElementById(`test-status-${serverId}`);
            if (!statusElement) return;
            
            let icon = 'fa-info-circle';
            let color = 'text-blue-600';
            
            switch (type) {
                case 'testing':
                    icon = 'fa-spinner fa-spin';
                    color = 'text-blue-600';
                    break;
                case 'completed':
                    icon = 'fa-check-circle';
                    color = 'text-green-600';
                    break;
                case 'error':
                    icon = 'fa-exclamation-circle';
                    color = 'text-red-600';
                    break;
            }
            
            statusElement.innerHTML = `<i class="fas ${icon} ml-1"></i>${status}`;
            statusElement.className = color;
        }
        
        // Show/hide test progress
        function showTestProgress(serverId, show) {
            const progressElement = document.getElementById(`test-progress-${serverId}`);
            if (!progressElement) return;
            
            if (show) {
                progressElement.classList.remove('hidden');
                progressElement.querySelector('div').style.width = '0%';
            } else {
                progressElement.classList.add('hidden');
            }
        }
        
        // Update progress bar
        function updateProgress(serverId, percent) {
            const progressElement = document.getElementById(`test-progress-${serverId}`);
            if (!progressElement) return;
            
            const progressBar = progressElement.querySelector('div');
            progressBar.style.width = percent + '%';
        }
        
        // Display test results
        function displayTestResults(serverId, results) {
            const metricsElement = document.getElementById(`test-metrics-${serverId}`);
            if (!metricsElement) return;
            
            // Update individual metrics
            document.getElementById(`ping-${serverId}`).textContent = results.ping;
            document.getElementById(`download-${serverId}`).textContent = results.download;
            document.getElementById(`upload-${serverId}`).textContent = results.upload;
            document.getElementById(`loss-${serverId}`).textContent = results.dataLoss + '%';
            
            // Show metrics
            metricsElement.classList.remove('hidden');
            
            // Update overall quality badge
            const qualityScore = calculateQualityScore(results);
            updateQualityBadge(serverId, qualityScore);
        }
        
        // Calculate quality score
        function calculateQualityScore(results) {
            let score = 0;
            
            // Ping score (lower is better)
            if (results.ping < 50) score += 25;
            else if (results.ping < 100) score += 20;
            else if (results.ping < 200) score += 15;
            else score += 5;
            
            // Download speed score
            if (results.download > 1000) score += 25;
            else if (results.download > 500) score += 20;
            else if (results.download > 200) score += 15;
            else score += 5;
            
            // Upload speed score
            if (results.upload > 500) score += 25;
            else if (results.upload > 200) score += 20;
            else if (results.upload > 100) score += 15;
            else score += 5;
            
            // Data loss score (lower is better)
            if (results.dataLoss === 0) score += 25;
            else if (results.dataLoss < 5) score += 15;
            else if (results.dataLoss < 10) score += 10;
            else score += 0;
            
            return score;
        }
        
        // Update quality badge
        function updateQualityBadge(serverId, score) {
            const statusElement = document.getElementById(`test-status-${serverId}`);
            if (!statusElement) return;
            
            let badgeClass = 'speed-badge good';
            let icon = 'fa-check-circle';
            let text = 'خوب';
            
            if (score >= 90) {
                badgeClass = 'speed-badge excellent';
                icon = 'fa-star';
                text = 'عالی';
            } else if (score >= 70) {
                badgeClass = 'speed-badge good';
                icon = 'fa-check-circle';
                text = 'خوب';
            } else if (score >= 50) {
                badgeClass = 'speed-badge average';
                icon = 'fa-clock';
                text = 'متوسط';
            } else {
                badgeClass = 'speed-badge poor';
                icon = 'fa-exclamation-triangle';
                text = 'ضعیف';
            }
            
            statusElement.innerHTML = `<span class="${badgeClass}"><i class="fas ${icon} ml-1"></i>${text}</span>`;
        }
        
        // Test all servers
        function testAllServers() {
            const speedCards = document.querySelectorAll('.speed-card');
            speedCards.forEach((card, index) => {
                const serverId = card.dataset.serverId;
                const domain = card.dataset.serverDomain;
                const port = card.dataset.serverPort;
                
                if (serverId && domain && port) {
                    setTimeout(() => {
                        runComprehensiveTest(parseInt(serverId), domain, parseInt(port));
                    }, index * 2000); // 2 second delay between tests
                }
            });
        }
        
        // Benchmark all servers (more intensive testing)
        function benchmarkAllServers() {
            showNotification('شروع تست عملکرد کامل...', 'info');
            testAllServers();
        }
        
        // Select speed server
        function selectSpeedServer(serverId, serverName, buttonElement) {
            <?php if (!$has_smart_sub): ?>
            showNotification('برای استفاده از این قابلیت، ابتدا باید اشتراک هوشمند ایجاد کنید.', 'warning');
            return;
            <?php endif; ?>
            
            if (buttonElement) {
                const originalContent = buttonElement.innerHTML;
                buttonElement.innerHTML = '<i class="fas fa-spinner fa-spin ml-2"></i>در حال تغییر...';
                buttonElement.disabled = true;
            }
            
            if (serverId) {
                showNotification(`در حال انتخاب ${serverName}...`, 'info');
            } else {
                showNotification('در حال حذف انتخاب...', 'info');
            }
            
            const form = document.createElement('form');
            form.method = 'POST';
            form.style.display = 'none';
            
            const actionInput = document.createElement('input');
            actionInput.type = 'hidden';
            actionInput.name = 'action';
            actionInput.value = 'select_speed_server';
            
            const serverIdInput = document.createElement('input');
            serverIdInput.type = 'hidden';
            serverIdInput.name = 'speed_server_id';
            serverIdInput.value = serverId || '';
            
            form.appendChild(actionInput);
            form.appendChild(serverIdInput);
            document.body.appendChild(form);
            form.submit();
        }
        
        // Modern notification system
        function showNotification(message, type = 'info') {
            const existingNotifications = document.querySelectorAll('.modern-notification');
            existingNotifications.forEach(notification => notification.remove());
            
            const notification = document.createElement('div');
            notification.className = 'modern-notification';
            
            let bgColor, textColor, icon;
            switch (type) {
                case 'success':
                    bgColor = '#10b981';
                    textColor = 'white';
                    icon = 'fa-check-circle';
                    break;
                case 'error':
                    bgColor = '#ef4444';
                    textColor = 'white';
                    icon = 'fa-exclamation-circle';
                    break;
                case 'warning':
                    bgColor = '#f59e0b';
                    textColor = 'white';
                    icon = 'fa-exclamation-triangle';
                    break;
                case 'info':
                default:
                    bgColor = '#3b82f6';
                    textColor = 'white';
                    icon = 'fa-info-circle';
                    break;
            }
            
            notification.style.cssText = `
                position: fixed;
                top: 20px;
                right: 20px;
                background-color: ${bgColor};
                color: ${textColor};
                padding: 12px 20px;
                border-radius: 8px;
                box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
                z-index: 10000;
                font-family: 'Vazirmatn', Tahoma, sans-serif;
                font-size: 14px;
                font-weight: 500;
                transform: translateX(100%);
                transition: transform 0.3s ease-in-out;
                max-width: 300px;
            `;
            
            notification.innerHTML = `
                <div style="display: flex; align-items: center;">
                    <i class="fas ${icon}" style="margin-left: 8px;"></i>
                    <span>${message}</span>
                </div>
            `;
            
            document.body.appendChild(notification);
            
            setTimeout(() => {
                notification.style.transform = 'translateX(0)';
            }, 10);
            
            if (type !== 'info') {
                setTimeout(() => {
                    notification.style.transform = 'translateX(100%)';
                    setTimeout(() => {
                        if (notification.parentNode) {
                            notification.remove();
                        }
                    }, 300);
                }, 3000);
            }
        }
    </script>
</body>
</html> 