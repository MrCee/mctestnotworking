<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>InvoicePlane – Setup Complete</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="NOINDEX,NOFOLLOW">

    <link rel="icon" href="/assets/core/img/favicon.png">
    <link rel="stylesheet" href="/assets/invoiceplane/css/welcome.css">

    <style>
        .container {
            max-width: 700px;
            margin: 60px auto;
            background: #fff;
            padding: 40px;
            border-radius: 6px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
        }

        h1 {
            margin-top: 0;
            color: #3c8dbc;
        }

        .alert {
            padding: 15px;
            border-radius: 5px;
            font-size: 15px;
            margin: 20px 0;
        }

        .alert-info {
            background-color: #e8f4fd;
            color: #31708f;
        }

        .alert-warning {
            background-color: #fcf8e3;
            color: #8a6d3b;
        }

        .spinner {
            margin: 30px auto;
            width: 60px;
            height: 60px;
            border: 6px solid #f3f3f3;
            border-top: 6px solid #3c8dbc;
            border-radius: 50%;
            animation: spin 1.2s linear infinite;
        }

        .btn {
            display: inline-block;
            margin-top: 20px;
            padding: 12px 24px;
            background: #3c8dbc;
            color: white;
            text-decoration: none;
            border-radius: 4px;
            font-weight: bold;
        }

        .btn:hover {
            background-color: #2e6da4;
        }

        #status-msg {
            font-size: 14px;
            color: #555;
            margin-top: 20px;
        }

        @keyframes spin {
            0%   { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>

<div class="container">
    <div class="install-panel">
        <h1 id="logo"><span>InvoicePlane</span></h1>

        <h2>Setup Complete</h2>

        <p>Your InvoicePlane installation has been successfully completed.</p>

        <div class="alert alert-info">
            The container is restarting to finalize setup. This may take a few seconds.
        </div>

        <div class="spinner"></div>

        <p id="status-msg">⏳ Waiting for container to come back online...</p>

        <p class="alert alert-warning">
            For security, edit your <code>ipconfig.php</code> and set: <strong>DISABLE_SETUP=true</strong>
        </p>

        <a href="/sessions/login" id="manual-link" class="btn" style="display:none;">
            ➡️ Go to Login
        </a>
    </div>
</div>

<script>
    setTimeout(() => {
        const ping = setInterval(() => {
            fetch("/sessions/login", { method: "HEAD" })
                .then(res => {
                    if (res.ok) {
                        clearInterval(ping);
                        document.getElementById("status-msg").innerText = "✅ Container is online. Redirecting...";
                        document.getElementById("manual-link").style.display = "inline-block";
                        setTimeout(() => {
                            window.location.href = "/sessions/login";
                        }, 2000);
                    }
                })
                .catch(() => {
                    document.getElementById("status-msg").innerText = "🌀 Still waiting for container...";
                });
        }, 1500);
    }, 5000);
</script>

</body>
</html>


