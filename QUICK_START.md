# ⚡ Quick Start Guide

## 🎯 5-Minute Deployment

```bash
# 1. Clone repository
git clone https://github.com/SergioKeiko/enterprise-automation-platform.git
cd enterprise-automation-platform

# 2. Configure environment
cp .env.example .env
nano .env  # Edit your domain and API keys

# 3. Deploy platform
docker-compose up -d
```

## 🌐 Access Services
- **n8n**: https://n8n.your-domain.com
- **Monitoring**: https://uptime.your-domain.com
- **Vector DB**: https://qdrant.n8n.your-domain.com
