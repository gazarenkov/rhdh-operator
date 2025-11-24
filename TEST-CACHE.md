This should create Backstage CR with persistent cache for dynamic plugins and StatefulSet with 2 replicas.

1. Make sure you have no deplyed operator (especially on non-default, 'rhdh-operator' namespace). If so, uninstall it first.

2. Deploy Operator on your cluster. Controller will be deployed to `rhdh-operator` namespace by default.
````shell
make deploy
````

3. Make sure that the patch like this is applied to your Backstage Custom Resource definition to enable persistent storage for dynamic plugins caching:
````yaml
spec:
  deployment:
    patch:
      spec:
        replicas: 2
        template:
          spec:
            volumes:
              - $patch: replace
                name: dynamic-plugins-root
                persistentVolumeClaim:
                  claimName: dynamic-plugins-root
        updateStrategy:
          type: RollingUpdate
        volumeClaimTemplates:
          - apiVersion: v1
            kind: PersistentVolumeClaim
            metadata:
              name: dynamic-plugins-root
            spec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 1Gi
````

4. Create Backstage Custom Resource on some namespace (make sure this namespace exists)
```shell
kubectl -n <your-namespace> apply -f <your-CR-file>.yaml
```
or using Openshift Developer Console.