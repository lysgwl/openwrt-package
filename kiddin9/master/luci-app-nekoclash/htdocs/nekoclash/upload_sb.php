<?php
$configDir = '/etc/neko/config/';

ini_set('memory_limit', '256M');

date_default_timezone_set('Asia/Shanghai');

if (!is_dir($configDir)) {
    mkdir($configDir, 0755, true);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_FILES['configFileInput'])) {
        $file = $_FILES['configFileInput'];
        $uploadFilePath = $configDir . basename($file['name']);

        if ($file['error'] === UPLOAD_ERR_OK) {
            if (move_uploaded_file($file['tmp_name'], $uploadFilePath)) {
                echo '配置文件上传成功：' . htmlspecialchars(basename($file['name']));
            } else {
                echo '配置文件上传失败！';
            }
        } else {
            echo '上传错误：' . $file['error'];
        }
    }

    if (isset($_POST['deleteConfigFile'])) {
        $fileToDelete = $configDir . basename($_POST['deleteConfigFile']);
        if (file_exists($fileToDelete) && unlink($fileToDelete)) {
            echo '配置文件删除成功：' . htmlspecialchars(basename($_POST['deleteConfigFile']));
        } else {
            echo '配置文件删除失败！';
        }
    }

    if (isset($_POST['oldFileName'], $_POST['newFileName'], $_POST['fileType'])) {
        $oldFileName = basename($_POST['oldFileName']);
        $newFileName = basename($_POST['newFileName']);
    
        if ($_POST['fileType'] === 'config') {
            $oldFilePath = $configDir . $oldFileName;
            $newFilePath = $configDir . $newFileName;
        } else {
            echo '无效的文件类型';
            exit;
        }

        if (file_exists($oldFilePath) && !file_exists($newFilePath)) {
            if (rename($oldFilePath, $newFilePath)) {
                echo '文件重命名成功：' . htmlspecialchars($oldFileName) . ' -> ' . htmlspecialchars($newFileName);
            } else {
                echo '文件重命名失败！';
            }
        } else {
            echo '文件重命名失败，文件不存在或新文件名已存在。';
        }
    }

    if (isset($_POST['editFile']) && isset($_POST['fileType'])) {
        $fileToEdit = $configDir . basename($_POST['editFile']);
        $fileContent = '';
        $editingFileName = htmlspecialchars($_POST['editFile']);

        if (file_exists($fileToEdit)) {
            $handle = fopen($fileToEdit, 'r');
            if ($handle) {
                while (($line = fgets($handle)) !== false) {
                    $fileContent .= htmlspecialchars($line);
                }
                fclose($handle);
            } else {
                echo '无法打开文件';
            }
        }
    }

    if (isset($_POST['saveContent'], $_POST['fileName'], $_POST['fileType'])) {
        $fileToSave = $configDir . basename($_POST['fileName']);
        $contentToSave = $_POST['saveContent'];
        file_put_contents($fileToSave, $contentToSave);
        echo '<p>文件内容已更新：' . htmlspecialchars(basename($fileToSave)) . '</p>';
    }

    if (isset($_GET['customFile'])) {
        $customDir = rtrim($_GET['customDir'], '/') . '/';
        $customFilePath = $customDir . basename($_GET['customFile']);
        if (file_exists($customFilePath)) {
            header('Content-Description: File Transfer');
            header('Content-Type: application/octet-stream');
            header('Content-Disposition: attachment; filename="' . basename($customFilePath) . '"');
            header('Expires: 0');
            header('Cache-Control: must-revalidate');
            header('Pragma: public');
            header('Content-Length: ' . filesize($customFilePath));
            readfile($customFilePath);
            exit;
        } else {
            echo '文件不存在！';
        }
    }
}

function formatFileModificationTime($filePath) {
    if (file_exists($filePath)) {
        $fileModTime = filemtime($filePath);
        return date('Y-m-d H:i:s', $fileModTime);
    } else {
        return '文件不存在';
    }
}

$configFiles = scandir($configDir);

if ($configFiles !== false) {
    $configFiles = array_diff($configFiles, array('.', '..'));
} else {
    $configFiles = []; 
}

function formatSize($size) {
    $units = array('B', 'KB', 'MB', 'GB', 'TB');
    $unit = 0;
    while ($size >= 1024 && $unit < count($units) - 1) {
        $size /= 1024;
        $unit++;
    }
    return round($size, 2) . ' ' . $units[$unit];
}
?>

<?php
$subscriptionPath = '/etc/neko/config/';
$dataFile = $subscriptionPath . 'subscription_data.json';

$message = "";
$defaultSubscriptions = [
    [
        'url' => '',
        'file_name' => 'config.json',
    ],
    [
        'url' => '',
        'file_name' => '',
    ],
    [
        'url' => '',
        'file_name' => '',
    ]
];

if (!file_exists($subscriptionPath)) {
    mkdir($subscriptionPath, 0755, true);
}

if (!file_exists($dataFile)) {
    file_put_contents($dataFile, json_encode(['subscriptions' => $defaultSubscriptions], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
}

$subscriptionData = json_decode(file_get_contents($dataFile), true);

if (!isset($subscriptionData['subscriptions']) || !is_array($subscriptionData['subscriptions'])) {
    $subscriptionData['subscriptions'] = $defaultSubscriptions;
}

if (isset($_POST['update_index'])) {
    $index = intval($_POST['update_index']);
    $subscriptionUrl = $_POST["subscription_url_$index"] ?? '';
    $customFileName = ($_POST["custom_file_name_$index"] ?? '') ?: 'config.json';

    if ($index < 0 || $index >= count($subscriptionData['subscriptions'])) {
        $message = "无效的订阅索引！";
    } elseif (empty($subscriptionUrl)) {
        $message = "订阅 $index 的链接为空！";
    } else {
        $subscriptionData['subscriptions'][$index]['url'] = $subscriptionUrl;
        $subscriptionData['subscriptions'][$index]['file_name'] = $customFileName;
        $finalPath = $subscriptionPath . $customFileName;

        $originalContent = file_exists($finalPath) ? file_get_contents($finalPath) : '';

        $ch = curl_init($subscriptionUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        $fileContent = curl_exec($ch);
        $error = curl_error($ch);
        curl_close($ch);

        if ($fileContent === false) {
            $message = "订阅 $index 无法下载文件。cURL 错误信息: " . $error;
        } else {
            $fileContent = str_replace("\xEF\xBB\xBF", '', $fileContent);

            $parsedData = json_decode($fileContent, true);
            if ($parsedData === null && json_last_error() !== JSON_ERROR_NONE) {
                file_put_contents($finalPath, $originalContent);
                $message = "订阅 $index 解析 JSON 数据失败！错误信息: " . json_last_error_msg();
            } else {
                if (isset($parsedData['inbounds'])) {
                    $newInbounds = [];

                    foreach ($parsedData['inbounds'] as $inbound) {
                        if (isset($inbound['type']) && $inbound['type'] === 'mixed' && $inbound['tag'] === 'mixed-in') {
                            $newInbounds[] = $inbound;
                        } elseif (isset($inbound['type']) && $inbound['type'] === 'tun') {
                            continue;
                        }
                    }

                    $newInbounds[] = [
                      "tag" => "tun",
                      "type" => "tun",
                      "inet4_address" => "172.19.0.0/30",
                      "inet6_address" => "fdfe:dcba:9876::0/126",
                      "stack" => "system",
                      "auto_route" => true,
                      "strict_route" => true,
                      "sniff" => true,
                      "platform" => [
                        "http_proxy" => [
                          "enabled" => true,
                          "server" => "0.0.0.0",
                          "server_port" => 7890
                        ]
                      ]
                    ];

                    $newInbounds[] = [
                      "tag" => "mixed",
                      "type" => "mixed",
                      "listen" => "0.0.0.0",
                      "listen_port" => 7890,
                      "sniff" => true
                    ];

                    $parsedData['inbounds'] = $newInbounds;
                }

                if (isset($parsedData['experimental']['clash_api'])) {
                    $parsedData['experimental']['clash_api'] = [
                        "external_ui" => "/etc/neko/ui/",
                        "external_controller" => "0.0.0.0:9090",
                        "secret" => "Akun"
                    ];
                }

                $fileContent = json_encode($parsedData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

                if (file_put_contents($finalPath, $fileContent) === false) {
                    $message = "订阅 $index 无法保存文件到: $finalPath";
                } else {
                    $message = "订阅 $index 更新成功！文件已保存到: {$finalPath}，并成功解析和替换 JSON 数据。";
                }
            }
        }

        file_put_contents($dataFile, json_encode($subscriptionData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
    }
}
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sing-box文件管理器</title>
    <link href="./assets/bootstrap/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #87ceeb;
            background-size: cover; 
            color: #E0E0E0; 
        }
        .container {
            background: rgba(30, 30, 30, 0.8); 
            border-radius: 10px;
            padding: 20px;
            margin-top: 50px; 
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.5); 
        }
        h1, h2 {
            color: #00FF7F; 
        }
        .table th, .table td {
            text-align: center;
            vertical-align: middle;
        }
        .editor {
            height: 300px; 
            width: 100%; 
            background-color: #2C2C2C; 
            color: #E0E0E0; 
            padding: 15px; 
            border: 1px solid #444;
            border-radius: 5px;
            font-family: monospace;
            margin-top: 20px;
            overflow: auto; 
        }
        .btn-danger {
            background-color: #CF6679; 
            color: #121212;
        }
        .btn-danger:hover {
            background-color: #B00020; 
        }
        .btn-success {
            background-color: #03DAC6; 
            color: #121212;
        }
        .btn-success:hover {
            background-color: #018786; 
        }
        .btn-warning {
            background-color: #F4B400; 
            color: #121212;
        }
        .btn-warning:hover {
            background-color: #C79400; 
        }
        .btn-primary {
            background-color: #03DAC6;
            border: none;
        }
        .btn-primary:hover {
            background-color: #018786;
        }
        .modal-header, .modal-body, .modal-footer {
            background: #f8f9fa;
            color: #333;
        }
        .modal-content {
            background: #ffffff;
            border: 1px solid #ced4da;
        }
        .modal-body {
            overflow-y: auto; 
        }
        .form-control {
            background-color: #2C2C2C;
            color: #E0E0E0;
            border: 1px solid #444;
        }
        .form-control:focus {
            border-color: #03DAC6;
            box-shadow: 0 0 0 0.2rem rgba(3, 218, 198, 0.25);
        }
        .log-output {
            background-color: #2C2C2C; 
            border: 1px solid #444;
            border-radius: 5px;
            color: #E0E0E0;
            padding: 10px;
            margin-top: 20px;
            height: 200px; 
            overflow-y: scroll; 
            white-space: pre-wrap; 
        }
        .subscription-card {
            background: #3C3C3C;
            border: 1px solid #444;
            color: #E0E0E0;
            margin-bottom: 20px;
        }
        .subscription-card .card-body {
            padding: 10px;
        }
        .custom-file-name {
            background-color: #2C2C2C; 
            color: #E0E0E0; 
            border: 1px solid #444;
        }
        .card .form-control {
            background-color: #2C2C2C; 
            color: #E0E0E0; 
            border: 1px solid #444;
        }
        .card .form-control:focus {
            border-color: #03DAC6;
            box-shadow: 0 0 0 0.2rem rgba(3, 218, 198, 0.25);
        }
        .form-inline .form-control-file {
            display: none; 
        }
        .btn-group {
            display: flex; 
            justify-content: center;
            gap: 10px; 
        }
        .btn-group .btn {
            height: 38px; 
            line-height: 1.5; 
            padding: 0 10px; 
            text-align: center;
        }
        .upload-btn {
            cursor: pointer;
        }
        .btn-group .btn-rename {
            max-width: 60px; 
            padding: 2px 6px; 
            font-size: 0.875rem; 
            width: auto; 
            white-space: nowrap; 
        }
        @media (max-width: 768px) {
            .btn-group {
                flex-direction: column;
            }
            .btn-group .btn {
                width: 100%;
                margin-bottom: 5px;
            }
            .nav-buttons {
                display: flex;
                flex-direction: column; 
                align-items: center;    
            }
            .nav-buttons .btn {
                width: 100%;            
                margin-bottom: 10px;   
            }
        }
    </style>
</head>
<body>
    <div class="container text-center">
        <h1 style="margin-top: 40px; margin-bottom: 20px;">Sing-box 文件管理</h1>
        <h2>配置文件管理</h2>
        
        <table class="table table-dark table-bordered">
            <thead>
                <tr>
                    <th>文件名</th>
                    <th>大小</th>
                    <th>修改时间</th>
                    <th>执行操作</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($configFiles as $file): ?>
                    <?php $filePath = $configDir . $file; ?>
                    <tr>
                        <td><a href="download.php?file=<?php echo urlencode($file); ?>"><?php echo htmlspecialchars($file); ?></a></td>
                        <td><?php echo file_exists($filePath) ? formatSize(filesize($filePath)) : '文件不存在'; ?></td>
                        <td><?php echo htmlspecialchars(date('Y-m-d H:i:s', filemtime($filePath))); ?></td>
                        <td>
                            <div class="btn-group">
                                <form action="" method="post" class="d-inline">
                                    <input type="hidden" name="deleteConfigFile" value="<?php echo htmlspecialchars($file); ?>">
                                    <button type="submit" class="btn btn-danger btn-sm" onclick="return confirm('确定要删除这个文件吗？');">删除</button>
                                </form>
                                <button type="button" class="btn btn-success btn-sm btn-rename" data-toggle="modal" data-target="#renameModal" data-filename="<?php echo htmlspecialchars($file); ?>">重命名</button>

                                <form action="" method="post" class="d-inline">
                                    <input type="hidden" name="editFile" value="<?php echo htmlspecialchars($file); ?>">
                                    <input type="hidden" name="fileType" value="config">
                                    <button type="submit" class="btn btn-warning btn-sm">编辑</button>
                                </form>
                                <form action="" method="post" enctype="multipart/form-data" class="form-inline d-inline upload-btn">
                                    <input type="file" name="configFileInput" class="form-control-file" required id="fileInput-<?php echo htmlspecialchars($file); ?>" onchange="this.form.submit()">
                                    <button type="button" class="btn btn-info" onclick="document.getElementById('fileInput-<?php echo htmlspecialchars($file); ?>').click();">上传</button>
                                </form>
                            </div>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>

        <?php if (isset($fileContent)): ?>
            <?php if (isset($_POST['editFile'])): ?>
                <?php $fileToEdit = $configDir . basename($_POST['editFile']); ?>
                <h2 class="mt-5">编辑文件: <?php echo $editingFileName; ?></h2>
                <p>最后更新日期: <?php echo date('Y-m-d H:i:s', filemtime($fileToEdit)); ?></p>
                <div class="editor-container">
                    <form action="" method="post">
                        <textarea name="saveContent" id="editor" class="editor"><?php echo $fileContent; ?></textarea><br>
                        <input type="hidden" name="fileName" value="<?php echo htmlspecialchars($_POST['editFile']); ?>">
                        <input type="hidden" name="fileType" value="<?php echo htmlspecialchars($_POST['fileType']); ?>">
                        <button type="submit" class="btn btn-primary mt-2" onclick="checkJsonSyntax()">保存内容</button>
                    </form>
                </div>
            <?php endif; ?>
        <?php endif; ?>

        <h1 style="margin-top: 20px; margin-bottom: 20px;">Sing-box 订阅</h1>
        <?php if ($message): ?>
            <p><?php echo nl2br(htmlspecialchars($message)); ?></p>
        <?php endif; ?>
        <form method="post">
            <div class="row">
                <?php for ($i = 0; $i < 3; $i++): ?>
                    <div class="col-md-4 mb-3">
                        <div class="card subscription-card p-2">
                            <div class="card-body p-2">
                                <h6 class="card-title">订阅链接 <?php echo $i + 1; ?></h6>
                                <div class="form-group mb-2">
                                    <input type="text" name="subscription_url_<?php echo $i; ?>" id="subscription_url_<?php echo $i; ?>" class="form-control form-control-sm" placeholder="订阅链接" value="<?php echo htmlspecialchars($subscriptionData['subscriptions'][$i]['url'] ?? ''); ?>">
                                </div>
                                <div class="form-group mb-2">
                                    <label for="custom_file_name_<?php echo $i; ?>">自定义文件名 <?php echo ($i === 0) ? '(固定为 config.json)' : ''; ?></label>
                                    <input type="text" name="custom_file_name_<?php echo $i; ?>" id="custom_file_name_<?php echo $i; ?>" class="form-control form-control-sm" value="<?php echo htmlspecialchars($subscriptionData['subscriptions'][$i]['file_name'] ?? ($i === 0 ? 'config.json' : '')); ?>" <?php echo ($i === 0) ? 'readonly' : ''; ?> >
                                </div>
                                <button type="submit" name="update_index" value="<?php echo $i; ?>" class="btn btn-info btn-sm">更新订阅 <?php echo $i + 1; ?></button>
                            </div>
                        </div>
                    </div>
                <?php endfor; ?>
            </div>
        </form>

        <div class="nav-buttons mt-4">
            <a href="javascript:history.back()" class="btn btn-success">返回上一级菜单</a>
            <a href="/nekoclash/upload_sb.php" class="btn btn-success">返回当前菜单</a>
            <a href="/nekoclash" class="btn btn-success">返回主菜单</a>
            <a href="/nekoclash/box.php" class="btn btn-success">打开订阅转换模板</a>
        </div>
    </div>

    <div class="modal fade" id="renameModal" tabindex="-1" role="dialog" aria-labelledby="renameModalLabel" aria-hidden="true">
        <div class="modal-dialog" role="document">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="renameModalLabel">重命名文件</h5>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close">
                        <span aria-hidden="true">&times;</span>
                    </button>
                </div>
                <div class="modal-body">
                    <form id="renameForm" action="" method="post">
                        <input type="hidden" name="oldFileName" id="oldFileName">
                        <div class="form-group">
                            <label for="newFileName">新文件名</label>
                            <input type="text" class="form-control" id="newFileName" name="newFileName" required>
                        </div>
                        <p>是否确实要重命名这个文件?</p>
                        <input type="hidden" name="fileType" value="config">
                        <div class="form-group text-right">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">取消</button>
                            <button type="submit" class="btn btn-primary">确定</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <script src="./assets/bootstrap/jquery-3.5.1.slim.min.js"></script>
    <script src="./assets/bootstrap/popper.min.js"></script>
    <script src="./assets/bootstrap/bootstrap.min.js"></script>
    <script>
        $('#renameModal').on('show.bs.modal', function (event) {
            var button = $(event.relatedTarget); 
            var oldFileName = button.data('filename'); 
            var modal = $(this);
            modal.find('#oldFileName').val(oldFileName); 
            modal.find('#newFileName').val(oldFileName); 
        });
    </script>
</body>
</html>
