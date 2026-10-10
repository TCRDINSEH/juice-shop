#!/bin/sh
set -eu

DATA_ROOT=/var/moodledata
CONFIG_IN_DATA="$DATA_ROOT/config.php"
CONFIG_IN_CODE=/var/www/moodle/config.php

if [ ! -d "$DATA_ROOT" ] || [ ! -w "$DATA_ROOT" ]; then
  echo "Moodle data volume is not mounted writable at $DATA_ROOT." >&2
  exit 1
fi

if [ -f "$CONFIG_IN_DATA" ]; then
  if [ ! -e "$CONFIG_IN_CODE" ]; then
    ln -s "$CONFIG_IN_DATA" "$CONFIG_IN_CODE"
  fi
else
  TOKEN=$(curl -fsS \
    -H 'Metadata-Flavor: Google' \
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' \
    | php -r '$v = json_decode(stream_get_contents(STDIN), true); echo $v["access_token"];')
  SERVICE_URI=$(curl -fsS \
    -H "Authorization: Bearer $TOKEN" \
    "https://run.googleapis.com/v2/projects/${GCP_PROJECT_ID}/locations/${GCP_REGION}/services/${MOODLE_SERVICE_NAME}" \
    | php -r '$v = json_decode(stream_get_contents(STDIN), true); echo $v["uri"] ?? "";')

  case "$SERVICE_URI" in
    https://*) ;;
    *)
      echo "Could not resolve the HTTPS URL for Cloud Run service $MOODLE_SERVICE_NAME." >&2
      exit 1
      ;;
  esac

  for attempt in $(seq 1 30); do
    if DB_SOCKET="$MOODLE_DB_SOCKET" \
      DB_NAME="$MOODLE_DB_NAME" \
      DB_USER="$MOODLE_DB_USER" \
      DB_PASSWORD="$MOODLE_DB_PASSWORD" \
      php -r 'mysqli_report(MYSQLI_REPORT_OFF); $db = @new mysqli("localhost", getenv("DB_USER"), getenv("DB_PASSWORD"), getenv("DB_NAME"), 3306, getenv("DB_SOCKET")); exit($db->connect_errno ? 1 : 0);'
    then
      break
    fi
    if [ "$attempt" -eq 30 ]; then
      echo "Could not connect to Cloud SQL through its Unix socket." >&2
      exit 1
    fi
    sleep 2
  done

  php /var/www/moodle/admin/cli/install.php \
    --non-interactive \
    --agree-license \
    --lang=en \
    --wwwroot="$SERVICE_URI" \
    --dataroot="$DATA_ROOT" \
    --dbtype=mysqli \
    --dbhost=localhost \
    --dbname="$MOODLE_DB_NAME" \
    --dbuser="$MOODLE_DB_USER" \
    --dbpass="$MOODLE_DB_PASSWORD" \
    --dbport=3306 \
    --dbsocket="$MOODLE_DB_SOCKET" \
    --prefix=mdl_ \
    --fullname="$MOODLE_SITE_FULLNAME" \
    --shortname="$MOODLE_SITE_SHORTNAME" \
    --adminuser="$MOODLE_ADMIN_USER" \
    --adminpass="$MOODLE_ADMIN_PASSWORD" \
    --adminemail="$MOODLE_ADMIN_EMAIL"

  if [ ! -f "$CONFIG_IN_CODE" ]; then
    echo "Moodle installer did not create config.php." >&2
    exit 1
  fi

  php -r '
    $path = $argv[1];
    $config = file_get_contents($path);
    $needle = "require_once(__DIR__ . \x27/lib/setup.php\x27);";
    $settings = "\$CFG->sslproxy = true;\n\$CFG->lock_factory = \x27\\\\core\\\\lock\\\\db_record_lock_factory\x27;\n";
    if (!str_contains($config, $needle)) {
        fwrite(STDERR, "Could not add Cloud Run Moodle settings to config.php.\n");
        exit(1);
    }
    file_put_contents($path, str_replace($needle, $settings . $needle, $config));
  ' "$CONFIG_IN_CODE"

  mv "$CONFIG_IN_CODE" "$CONFIG_IN_DATA"
  ln -s "$CONFIG_IN_DATA" "$CONFIG_IN_CODE"
fi

exec "$@"
