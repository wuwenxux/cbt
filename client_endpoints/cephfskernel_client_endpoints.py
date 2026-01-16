import common

from .ceph_client_endpoints import CephClientEndpoints

class CephfsKernelClientEndpoints(CephClientEndpoints):
    def create(self):
        self.create_fs()

    def mount(self):
        self.mount_fs()

    def mount_fs_helper(self, node, dir_name):
        # 如果secret文件不存在，从keyring生成它（适用于use_existing=True的情况）
        # 使用keyring文件路径：/etc/ceph/ceph.client.admin.keyring
        keyring_path = self.client_keyring
        # 如果keyring是默认路径但文件不存在，尝试使用ceph.client.admin.keyring
        if keyring_path == '/etc/ceph/ceph.keyring':
            keyring_path = '/etc/ceph/ceph.client.admin.keyring'
        gen_secret_cmd = 'sudo sh -c \'if [ ! -f %s ]; then %s --print-key %s > %s 2>/dev/null && chmod 600 %s; fi\'' % (self.client_secret, self.cluster.ceph_authtool_cmd, keyring_path, self.client_secret, self.client_secret)
        common.pdsh(node, gen_secret_cmd, continue_if_error=True).communicate()
        cmd = 'sudo %s %s:/ %s -o name=admin,secretfile=%s,mds_namespace=%s' % (self.mount_cmd, ','.join(self.mon_addrs), dir_name, self.client_secret, self.name)
        common.pdsh(node, cmd, continue_if_error=False).communicate()

    def create_recovery_image(self):
        self.create_rbd_recovery()
