<?php
// rcguard: Cloudflare Turnstile a ogni login. Le chiavi arrivano da webmail.env (mai in git).
$config['failed_attempts'] = 0;
$config['expire_time'] = 30;
$config['rcguard_reset_after_success'] = true;
$config['recaptcha_api_version'] = 'v2cfturnstile';
$config['recaptcha_api_url'] = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
$config['recaptcha_publickey'] = getenv('TURNSTILE_SITE_KEY');
$config['recaptcha_privatekey'] = getenv('TURNSTILE_SECRET_KEY');
$config['recaptcha_send_client_ip'] = true;
$config['recaptcha_proxy'] = false;
$config['recaptcha_proxy_auth'] = false;
$config['recaptcha_log'] = true;
$config['recaptcha_theme'] = 'auto';
$config['recaptcha_size'] = 'normal';
$config['recaptcha_log_success'] = 'Verification succeeded for %u. [%r]';
$config['recaptcha_log_failure'] = 'Error: Verification failed for %u. [%r]';
$config['recaptcha_log_unknown'] = 'Error: Unknown log type.';
$config['rcguard_ipv6_prefix'] = 64;
$config['rcguard_ignore_ips'] = [];
$config['recaptcha_whitelist'] = [];
