import common
import settings

from .ceph_client_endpoints import CephClientEndpoints

class CephfsKernelClientEndpoints(CephClientEndpoints):
    def create(self):
        self.create_fs()

    def mount(self):
        self.mount_fs()

    def mount_fs_helper(self, node, dir_name):
        # 如果secret文件不存在，从keyring生成它（适用于use_existing=True的情况）
        keyring_path = self.client_keyring
        if keyring_path == '/etc/ceph/ceph.keyring':
            keyring_path = '/etc/ceph/ceph.client.admin.keyring'
        gen_secret_cmd = 'sudo sh -c \'if [ ! -f %s ]; then %s --print-key %s > %s 2>/dev/null && chmod 600 %s; fi\'' % (self.client_secret, self.cluster.ceph_authtool_cmd, keyring_path, self.client_secret, self.client_secret)
        common.pdsh(node, gen_secret_cmd, continue_if_error=True).communicate()

        # 构建 MON 地址列表（格式: ip1:port,ip2:port,...）
        mon_str = ','.join(self.mon_addrs)
        # 去掉端口，只保留 IP（内核 mount -t ceph 不接受带端口的地址）
        mon_ips = ','.join(addr.split(':')[0] for addr in self.mon_addrs)

        # 使用兼容性更好的 mount -t ceph 旧格式，支持所有 Ceph 版本
        # 格式: mount -t ceph <mon_ip1>,<mon_ip2>,...:/ <mountpoint> -o name=admin,secretfile=...
        cmd = 'sudo mount -t ceph %s:/ %s -o name=admin,secretfile=%s' % (
            mon_ips, dir_name, self.client_secret)
        common.pdsh(node, cmd, continue_if_error=False).communicate()

    def create_recovery_image(self):
        self.create_rbd_recovery()
