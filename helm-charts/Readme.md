To install gpu-operator and kai run the following command
```ShellSession
$ cd gpu-operator
$ helm install gpu-operator -n gpu-operator --create-namespace .
$ cd ../kai-scheduler
$ helm install kai-schedular -n kai-schedular --create-namespace .
$ cd ..
# To create the queue
$ kubectl create -f queue.yaml
# To run the pod using kai-schedular
$ kubectl create -f kai-pod.yaml
```
