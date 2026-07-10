DELETE FROM setting WHERE key = 'disableAuth';
INSERT INTO setting (key, value) VALUES ('disableAuth', 'true');

UPDATE monitor
SET
  active = 1,
  user_id = 1,
  interval = 60,
  retry_interval = 60,
  maxretries = 3,
  type = 'http',
  url = 'https://nextcloud.nakasyou.how/status.php',
  accepted_statuscodes_json = '["200-299"]',
  method = 'GET'
WHERE name = 'Nextcloud';

INSERT INTO monitor (
  name,
  active,
  user_id,
  interval,
  retry_interval,
  maxretries,
  type,
  url,
  accepted_statuscodes_json,
  method
)
SELECT
  'Nextcloud',
  1,
  1,
  60,
  60,
  3,
  'http',
  'https://nextcloud.nakasyou.how/status.php',
  '["200-299"]',
  'GET'
WHERE changes() = 0;

UPDATE monitor
SET
  active = 1,
  user_id = 1,
  interval = 60,
  retry_interval = 60,
  maxretries = 3,
  type = 'http',
  url = 'https://csbie.nakasyou.how/',
  accepted_statuscodes_json = '["200-299"]',
  method = 'GET'
WHERE name = 'csbie';

INSERT INTO monitor (
  name,
  active,
  user_id,
  interval,
  retry_interval,
  maxretries,
  type,
  url,
  accepted_statuscodes_json,
  method
)
SELECT
  'csbie',
  1,
  1,
  60,
  60,
  3,
  'http',
  'https://csbie.nakasyou.how/',
  '["200-299"]',
  'GET'
WHERE changes() = 0;
