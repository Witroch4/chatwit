-- ============================================
-- REMOVER TELEMETRIA DO BANCO DE DADOS
-- ============================================

-- Remove tokens de analytics
UPDATE global_configs 
SET value = '' 
WHERE name IN ('ANALYTICS_TOKEN', 'HELP_CENTER_ANALYTICS_ID');

-- Remove configuracoes de suporte Chatwoot
UPDATE global_configs 
SET value = '' 
WHERE name IN (
    'CHATWOOT_INBOX_TOKEN',
    'CHATWOOT_INBOX_HMAC_KEY', 
    'CHATWOOT_SUPPORT_WEBSITE_TOKEN',
    'CHATWOOT_SUPPORT_SCRIPT_URL',
    'CHATWOOT_SUPPORT_IDENTIFIER_HASH'
);

-- Opcional: Remove identificador de instalacao (descomentar se necessario)
-- DELETE FROM installation_configs WHERE name = 'INSTALLATION_IDENTIFIER';

-- Verifica configuracoes aplicadas
SELECT name, 
       CASE WHEN value = '' THEN 'REMOVIDO' ELSE 'AINDA PRESENTE' END as status
FROM global_configs 
WHERE name IN (
    'ANALYTICS_TOKEN', 
    'HELP_CENTER_ANALYTICS_ID',
    'CHATWOOT_INBOX_TOKEN',
    'CHATWOOT_INBOX_HMAC_KEY',
    'CHATWOOT_SUPPORT_WEBSITE_TOKEN', 
    'CHATWOOT_SUPPORT_SCRIPT_URL',
    'CHATWOOT_SUPPORT_IDENTIFIER_HASH'
);
