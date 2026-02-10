In other words, the default configuration defines the set of resources the Operator should create and manage when the user applies an empty Backstage Custom Resource, like this:

`apiVersion: backstage.redhat.com/v1alpha5
kind: Backstage
metadata:
name: my-rhdh-instance
namespace: rhdh`

Here is the list of resources created in the specified namespace (`rhdh` in the example above) by default based on the default configuration:

| File Name             | Resource GVK                     | Resource Name                           | Description                                                                                         |
|-----------------------|----------------------------------|-----------------------------------------|-----------------------------------------------------------------------------------------------------|
| deployment.yaml       | apps/v1/Deployment               | backstage-{cr-name}                     | The main Backstage application deployment. Mandatory                                                |
| service.yaml          | v1/Service                       | backstage-{cr-name}                     | The Backstage application service. Mandatory                                                        |
| db-statefulset.yaml   | apps/v1/StatefulSet              | backstage-psql-{cr-name}                | The PostgreSQL database stateful set. Needed if spec.enabledDb=true                                 |
| db-service.yaml       | v1/Service                       | backstage-psql-{cr-name}                | The PostgreSQL database service. Needed if spec.enabledDb=true                                      |   
| db-secret.yaml        | v1/Secret                        | backstage-psql-{cr-name}                | The PostgreSQL database credentials secret. Needed if spec.enabledDb=true                           | 
| route.yaml            | route.openshift.io/v1            | backstage-{cr-name}                     | The OpenShift Route to expose Backstage externally. Optional, applied to Openshift only             |   
| app-config.yaml       | v1/ConfigMap                     | backstage-config-{cr-name}              | Specifies one or more Backstage app-config.yaml files. Optional                                     | 
| configmap-files.yaml  | v1/ConfigMap                     | backstage-files-{cr-name}               | Specifies additional ConfigMaps to be mounted as files into Backstage Pod. Optional                 |
| configmap-envs.yaml   | v1/ConfigMap                     | backstage-envs-{cr-name}                | Specifies additional ConfigMaps to be exposed as environment variables into Backstage Pod. Optional | 
| secret-files.yaml     | v1/Secret   or                   | backstage-files-{cr-name}               | Specifies additional Secrets to be mounted as files into Backstage Pod. Optional                    | 
|                       | list of v1/Secret                | backstage-files-{cr-name}-{secret-name} |                                                                                                     |
| secret-envs.yaml      | v1/Secret   or                   | backstage-envs-{cr-name}                | Specifies additional Secrets to be exposed as environment variables into Backstage Pod. Optional    |
|                       | list of v1/Secret                | backstage-envs-{cr-name}-{secret-name}  |                                                                                                     |
| dynamic-plugins.yaml  | v1/ConfigMap                     | backstage-dynamic-plugins-{cr-name}     | Specifies dynamic plugins to be installed into Backstage instance. Optional                         | 
| pvcs.yaml             | list of v1/PersistentVolumeClaim | backstage-{cr-name}-{pvc-name}          | The Persistent Volume Claim for PostgreSQL database. Optional.                                      | 

NOTE: The {cr-name} is the name of the Backstage Custom Resource, e.g. 'my-rhdh-instance' in the example above.
NOTE: It is not expected that user manages these resources manually. The Operator will take care of creating, updating and deleting them as necessary.

### Default mount path

Some objects, such as: app-config, configmap-files, secret-files, dynamic-plugins, pvcs, are mounted to the Backstage Container as files or directories. Default mount path is Container's WorkingDir, if not defined it falls to "/opt/app-root/src".

### Annotations

We use annotations to configure some objects. The following annotations are supported:

#### rhdh.redhat.com/mount-path to configure mount path.

If specified, the object will be mounted to the specified path, otherwise [Default mount path](#default-mount-path) will ve used.
It is possible to specify relative path, which will be appended to the default mount path.

Supported objects: **pvcs, secret-files**.

Examples:

_**pvcs.yaml**_
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myclaim
  annotations:
    rhdh.redhat.com/mount-path: /mount/path/from/annotation
...
```

In the example above the PVC called **myclaim** will be mounted to **/mount/path/from/annotation** directory

_**secret-files.yaml**_
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
  annotations:
    rhdh.redhat.com/mount-path: /mount/path/from/annotation
...
```
In the example above the Secret called **mysecret** will be mounted to **/mount/path/from/annotation** directory

#### rhdh.redhat.com/containers for mounting volume to specific container(s)

Supported objects: **pvcs, secret-files, secret-envs**.

Options:

* No or empty annotation: the volume will be mounted to the Backstage container only
* \* (asterisk): the volume will be mounted to all the containers
* Otherwise, container names separated by commas will be used

Examples:

_**pvcs.yaml**_
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myclaim
  annotations:
    rhdh.redhat.com/containers: "init-dynamic-plugins,backstage-backend"
...
```
In the example above the PVC called **myclaim** will be mounted to **init-dynamic-plugins** and **backstage-backend** containers

_**secret-envs.yaml**_

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
  annotations:
    rhdh.redhat.com/containers: "*"
...
```
In the example above the PVC called **myclaim** will be mounted to all the containers

### Metadata Generation

For Backstage to function consistently at runtime, certain metadata values need to be predictable. Therefore, the Operator generates values according to the following rules. Any value for these fields specified in either Default or Raw Configuration will be replaced by the generated values.

For All the objects **metadata.name** is generated according to the rules defined in the [Default Configuration files](#default-configuration-files), column **Object name**. <cr-name> means a Name of Backstage Custom Resource owning this configuration.
For example, Backstage CR named **mybackstage** will create K8s Deployment resource called **backstage-mybackstage**. Specific, per-object generated metadata described below.

* deployment.yaml
    - `spec.selector.matchLabels[rhdh.redhat.com/app] = backstage-<cr-name>`
    - `spec.template.metadata.labels[rhdh.redhat.com/app] = backstage-<cr-name>`
* service.yaml
    - `spec.selector[rhdh.redhat.com/app] = backstage-<cr-name>`
* db-statefulset.yaml
    - `spec.selector.matchLabels[rhdh.redhat.com/app] = backstage-psql-<cr-name>`
    - `spec.template.metadata.labels[rhdh.redhat.com/app] = backstage-psql-<cr-name>`
* db-service.yaml
    - `spec.selector[rhdh.redhat.com/app] = backstage-psql-<cr-name>`

### Multi objects

Since version **0.4.0**, Operator supports multi objects which mean the object type(s) marked as Multi=true in the table above can be declared and added to the model as the list of objects of certain type. To do so multiple objects are added to the yaml file using "---" delimiter.

For example, adding the following code snip to **pvcs.yaml** will cause creating 2 PVCs called **backstage-&lt;cr-name&gt;-myclaim1** and **backstage-&lt;cr-name&gt;-myclaim2** and mounting them to Backstage container accordingly.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myclaim1
...
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myclaim2
...
```

### Default base URLs

Since version 0.6.0, the Operator may set the base URLs fields in the default app-config ConfigMap (named `backstage-appconfig-<CR_name>`) created per CR, based on the [Route](#route) parameters and the [OpenShift cluster ingress domain](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/networking/networking-operators#nw-ne-openshift-ingress_configuring-ingress).

Below are the rules currently governing this behavior:

- No change if the cluster is not OpenShift.
- No change if `spec.application.route.enabled` is explicitly set to `false` in the CR
- The base URLs are set to `https://<spec.application.route.host>` if `spec.application.route.host` is set in the Backstage CR.
- The base URLs are set to `https://<spec.application.route.subdomain>.<cluster_ingress_domain>` if `spec.application.route.subdomain` is set in the Backstage CR.
- The base URLs are set to `https://backstage-<CR_name>-<namespace>.<cluster_ingress_domain>`, which is the domain set by default for the Route object created by the Operator.

The following app-config fields might be updated in this default app-config ConfigMap:
- `app.baseUrl`
- `backend.baseUrl`
- `backend.cors.origin`

Note that this behavior is done on a best-effort basis and only on OpenShift.

In any case (error or on non-OpenShift clusters), users still have the ability to override such defaults by providing custom app-config ConfigMap(s), as depicted in the [app-config](#app-config) section.

## Raw Configuration

Raw Configuration consists of the same YAML manifests as the Default configuration, but is specific to each Custom Resource (CR). You can override any or all Default configuration keys (e.g., for `deployment.yaml`) or add new keys not defined in the Default configuration by specifying them in ConfigMaps.

Here’s a fragment of the Backstage spec containing Raw configuration:

```yaml
spec:
  rawRuntimeConfig:
    backstageConfig: <configMap-name>  # to use for all manifests except db-*.yaml
    localDbConfig: <configMap-name>    # to use for db-*.yaml manifests
```

**NOTE:** While the Backstage Application config is separated from Database Configuration, it makes no difference which ConfigMap you use for which object; they are ultimately merged into one structure. Just avoid using the same keys in both.
