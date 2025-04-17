output "instance_ips" {
  description = "IPv4 and IPv6 addresses of the created instances"
  value = {
    for region, instance in module.linode_instances : region => {
      # convert the single‐element set to a list, grab index 0
      ipv4 = tolist(instance.ipv4_address)[0]

      # strip off the /128 on the CIDR
      ipv6 = replace(instance.ipv6_address, "/128", "")

      # display fqdn
      fqdn = "${instance.instance_label}.${var.tld}"
    }
  }
}