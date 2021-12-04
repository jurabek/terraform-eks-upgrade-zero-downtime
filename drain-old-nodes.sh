OLD_VERSION=1.20
OLD_NODES=$(kubectl get nodes | grep $OLD_VERSION | awk '{ print $1 }')

#Run kubectl taint nodes on each old node to prevent new pods from being scheduled on them
for node in $OLD_NODES;
do
    kubectl taint nodes $node key=value:NoSchedule
done

# Drain the old nodes and force the pods to move to new nodes.
for node in $OLD_NODES;
do
    kubectl drain $node --grace-period=60 --ignore-daemonsets=true --delete-emptydir-data=true
done