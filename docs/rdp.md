# remote desktop protocol

## sharing a local folder/drive over rdp
I have a scheduled task that runs a script that automatically mounts a few folders that I need access to on remote servers. Currently, I use it to share my scripts folder as keeping a copy of the scripts on each server is a pain and I often forget to update them. By sharing the folder over rdp, I can access the latest version of the scripts without having to worry about copying them to each server.

### mounting a folder as a drive
1. open powershell
2. use the subst command to mount the folder as a drive, for example:

```
subst X: C:\path\to\folder
```

### sharing the drive over rdp
1. open remote desktop connection
2. click show options
3. click local resources
4. click more
5. check the box next to the drive you want to share
6. click ok
7. connect to the remote desktop

### accessing this shared drive on the remote desktop
you can access the shared drive either by using file explorer or with powershell using `\\tsclient\X ` where X is the drive letter you assigned to the folder.
