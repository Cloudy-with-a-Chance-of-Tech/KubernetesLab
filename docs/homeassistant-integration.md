# Home Assistant Integration with Prometheus and Grafana

## 📱 Overview

The monitoring stack is configured to automatically collect metrics from Home Assistant and display them in Grafana dashboards. This integration provides visibility into IoT sensors, switches, and device states alongside Kubernetes cluster metrics.

## 🔧 Configuration Components

### 1. Prometheus Scraping Configuration

**Location**: `monitoring/prometheus/prometheus-config.yaml`

```yaml
# Home Assistant metrics
- job_name: 'homeassistant'
  scrape_interval: 60s
  metrics_path: /api/prometheus
  scheme: https
  bearer_token_file: /etc/prometheus/secrets/homeassistant-token/token
  tls_config:
    insecure_skip_verify: true  # Adjust based on your HA SSL setup
  static_configs:
    - targets: ['homeassistant.homelab.local:8123']
  relabel_configs:
    - source_labels: [__name__]
      target_label: source
      replacement: homeassistant
```

### 2. Secret Management

**Location**: `monitoring/secrets/homeassistant-secret.yaml`

- **Secret Name**: `homeassistant-token`
- **Namespace**: `monitoring`
- **Data**: Long-lived access token from Home Assistant
- **Mount Path**: `/etc/prometheus/secrets/homeassistant-token/token`

### 3. CI/CD Integration

**Location**: `.github/workflows/gitops-deploy.yml`

The pipeline automatically creates the secret from the `HOMEASSISTANT_TOKEN` environment variable:

```bash
kubectl create secret generic homeassistant-token \
  --from-literal=token="$HOMEASSISTANT_TOKEN" \
  --namespace=monitoring
```

## 📊 Grafana Dashboard

**Location**: `monitoring/grafana/dashboards/homeassistant.json`

### Dashboard Features:
- **Temperature Sensors**: Real-time temperature readings in Celsius
- **Humidity Sensors**: Humidity percentages with color-coded thresholds
- **Power Consumption**: Time-series power usage in watts
- **Switch States**: ON/OFF status with color indicators
- **Binary Sensors**: OPEN/CLOSED states for doors, windows, etc.

### Dashboard Configuration:
- **UID**: `homeassistant`
- **Update Interval**: 10 seconds via file provisioning
- **Time Range**: Last 24 hours
- **Auto-refresh**: Enabled

## 🏠 Home Assistant Requirements

### Required Configuration

Add to your Home Assistant `configuration.yaml`:

```yaml
prometheus:
  namespace: hass
  filter:
    include_domains:
      - sensor
      - switch
      - binary_sensor
      - light
      - climate
    exclude_entity_globs:
      - sensor.weather_*
  component_config_glob:
    sensor.*_temp:
      override_metric: temperature_c
    sensor.*_hum:
      override_metric: humidity_percent
    sensor.*_power:
      override_metric: power_w
```

### Long-Lived Access Token

1. **Generate Token**:
   - Go to Home Assistant → Profile → Security
   - Create "Long-lived access token"
   - Copy the token value

2. **Add to GitHub Secrets**:
   - Repository → Settings → Secrets and Variables → Actions
   - Add `HOMEASSISTANT_TOKEN` with the token value

## 🌐 Network Configuration

### Home Assistant Endpoint
- **URL**: `homeassistant.homelab.local:8123`
- **Protocol**: HTTPS
- **Metrics Path**: `/api/prometheus`
- **Authentication**: Bearer token

### Network Requirements
- Home Assistant must be accessible from Kubernetes cluster
- DNS resolution for `homeassistant.homelab.local`
- Port 8123 accessible from monitoring namespace

## 🔍 Verification Steps

### 1. Check Secret Creation
```bash
kubectl get secret homeassistant-token -n monitoring
kubectl describe secret homeassistant-token -n monitoring
```

### 2. Verify Prometheus Target
```bash
# Access Prometheus UI
curl http://192.168.100.100:9090/targets
# Look for "homeassistant" job status
```

### 3. Test Home Assistant Metrics
```bash
# Query Prometheus for HA metrics
curl "http://192.168.100.100:9090/api/v1/query?query={source=\"homeassistant\"}"
```

### 4. Check Grafana Dashboard
- Navigate to `http://192.168.100.101:3000`
- Go to Dashboards → "Home Assistant Monitoring"
- Verify data is displaying

## 🚨 Troubleshooting

### Common Issues

#### 1. Authentication Failed
- **Symptom**: Prometheus target shows "401 Unauthorized"
- **Solution**: Verify `HOMEASSISTANT_TOKEN` in GitHub secrets
- **Check**: Token is valid and not expired

#### 2. Network Connectivity
- **Symptom**: Prometheus target shows "Connection refused"
- **Solution**: Verify Home Assistant URL and network access
- **Check**: DNS resolution and port accessibility

#### 3. No Metrics Appearing
- **Symptom**: Empty Grafana dashboard
- **Solution**: Check Home Assistant Prometheus integration
- **Check**: `prometheus:` configuration in HA config

#### 4. Dashboard Not Loading
- **Symptom**: Dashboard missing from Grafana
- **Solution**: Check ConfigMap and file provisioning
- **Check**: Dashboard JSON in grafana-dashboards ConfigMap

### Debug Commands

```bash
# Check Prometheus config
kubectl get configmap prometheus-config -n monitoring -o yaml

# Check dashboard ConfigMap
kubectl get configmap grafana-dashboards -n monitoring -o yaml

# View Prometheus logs
kubectl logs -n monitoring deployment/prometheus

# View Grafana logs
kubectl logs -n monitoring deployment/grafana
```

## 🔄 Update Process

### Adding New Metrics

1. **Update Home Assistant**: Add new sensors to HA configuration
2. **Modify Dashboard**: Edit `homeassistant.json` dashboard file
3. **Deploy Changes**: Commit and push to trigger CI/CD
4. **Verify**: Check dashboard updates automatically within 10 seconds

### Dashboard Customization

Dashboard files are automatically loaded via:
- **File Provisioning**: `updateIntervalSeconds: 10`
- **ConfigMap Volume**: Mounted at `/var/lib/grafana/dashboards`
- **Auto-Detection**: No restart required

## 📋 Metrics Reference

### Available Metrics

| Metric Type | Example | Unit | Description |
|-------------|---------|------|-------------|
| Temperature | `temperature_c` | Celsius | Temperature sensor readings |
| Humidity | `humidity_percent` | Percent | Humidity sensor readings |
| Power | `power_w` | Watts | Power consumption |
| Switch | `switch_state` | 0/1 | Switch on/off state |
| Binary Sensor | `binary_sensor_state` | 0/1 | Door/window open/closed |

### Labels

All Home Assistant metrics include:
- `source="homeassistant"` - Identifies metrics source
- `friendly_name` - Human-readable sensor name
- `entity_id` - Home Assistant entity identifier

## 🔐 Security Considerations

- **Token Storage**: Secured as Kubernetes secret
- **Network Access**: Internal cluster communication
- **TLS Configuration**: Adjust `insecure_skip_verify` based on HA SSL setup
- **Access Control**: Metrics accessible only within monitoring namespace

## 📈 Monitoring Best Practices

1. **Regular Token Rotation**: Update tokens quarterly
2. **Metric Filtering**: Exclude unnecessary sensors to reduce load
3. **Dashboard Optimization**: Use appropriate time ranges
4. **Alert Configuration**: Set up alerts for critical sensors
5. **Backup Dashboards**: Version control dashboard JSON files
