import common
import time

from .ceph_client_endpoints import CephClientEndpoints

class CephfsFuseClientEndpoints(CephClientEndpoints):
    def create(self):
        self.create_fs()

    def mount(self):
        self.mount_fs()

    def mount_fs_helper(self, node, dir_name):
        # ceph-fuse 默认前台运行，需要在后台运行并等待挂载完成
        # 先尝试卸载（如果已挂载）
        umount_cmd = 'sudo umount %s 2>/dev/null || true' % dir_name
        common.pdsh(node, umount_cmd, continue_if_error=True).communicate()
        
        # 在后台启动 ceph-fuse
        cmd = 'sudo nohup %s -c %s %s > /dev/null 2>&1 &' % (self.ceph_fuse_cmd, self.tmp_conf, dir_name)
        common.pdsh(node, cmd, continue_if_error=False).communicate()
        
        # 等待挂载完成（最多等待10秒）
        max_wait = 10
        wait_interval = 0.5
        for i in range(int(max_wait / wait_interval)):
            time.sleep(wait_interval)
            check_cmd = 'mountpoint -q %s && echo "mounted" || echo "not_mounted"' % dir_name
            stdout, stderr = common.pdsh(node, check_cmd, continue_if_error=True).communicate()
            if 'mounted' in stdout:
                return
        # 如果超时仍未挂载，检查进程是否在运行
        check_proc_cmd = 'pgrep -f "ceph-fuse.*%s" > /dev/null && echo "running" || echo "not_running"' % dir_name
        stdout, stderr = common.pdsh(node, check_proc_cmd, continue_if_error=True).communicate()
        if 'not_running' in stdout:
            raise Exception('ceph-fuse failed to start on %s' % node)

    def create_recovery_image(self):
        self.create_rbd_recovery()
