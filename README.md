# k8s-dynamic-node-operator


## Index Directory

### Run command

```sh
docker run --rm --name index-directory \
    -v $(pwd)/index-directory/nginx.conf:/etc/nginx/nginx.conf:ro \
    -v $(pwd)/app:/app:ro \
    -p 8080:80 \
    nginx
```
