# SSM Converge — Reference Examples

These configurations illustrate how to express common patterns with the SSM Converge DSL but **have not been validated end-to-end on EC2**. Treat them as starting points, not drop-in ready.

| File | Why it's in reference/ |
|------|------------------------|
| `webserver-baseline.sh` | References `s3://DOC-EXAMPLE-BUCKET/nginx/nginx.conf` that doesn't exist. Upload your own nginx.conf and update the `source` path before running. |
| `apache-tomcat.sh` | References `s3://DOC-EXAMPLE-BUCKET/tomcat/apache-tomcat-9.0.87.tar.gz`. Stage the tarball in your own bucket, update the path, and test before fleet rollout. |
| `postgresql-server.sh` | Needs ≥ 2 GB RAM (t3.small+). The `initdb` handler is fragile across distros and may need tweaking per base AMI. |
| `app-deploy.sh` | Assumes Node.js is installed and that `myapp.service` points at a real application tree. Adapt the systemd unit and app paths for your deployment. |

## Running them

Same as the validated examples:

```bash
sudo DSC_MODE=audit   DSC_PROFILE=myapp bash examples/reference/app-deploy.sh
sudo DSC_MODE=enforce DSC_PROFILE=myapp bash examples/reference/app-deploy.sh
```

## Graduating a reference example

Once you've adapted one to your environment and validated it end-to-end on a real instance, consider moving it back into `examples/` so the pattern is more discoverable.
