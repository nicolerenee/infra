# Nicole's Infra Repo (aka gitops)

**WARNING:** This repo is undergoing major changes. The `kubernetes` and `apps`
directory are the current iteration and are under going major restructuring.

## What is all of this?

This repo contains files that help build out my kubernetes cluster that I run in
my home lab. There are a lot of components in here, but if you are looking to
run this yourself these are some places to start.

This repo is constantly being applied to my cluster with
[flux]. It has a lot of features, but quite possible my favorite one is that
with anootations you it will monitor the image tags available for the image you
have deployed and update it automatically, and even push a commit back into the
repo to track the change.

Any secrets in this registry are protected with [sealed secrets]. This allows me
to check them into this repo even though it is public.

I'm running this on bare metal and I like being able to use the `LoadBalancer`
type for my services. To facalitate this I run [metallb]. I'm running this in
bgp mode on my network. I use UniFi hardware throughout my network, however BGP
isn't something you can configure through the UI. Included in the repo is the
`config.gateway.json` that I use on my UniFi server to configure BGP and a few
other things. To learn more about how you can set this up check out these
[docs][usg-config].

### How do I set this up myself?
Checkout the [bootstrap.sh] script as a starting point. This repo is very
specific to me, so don't expect to just being to run it and everything work for
you, but you should feel free to fork it and tweak it to fit your needs.

### I have questions?
Awesome! Feel free to reach out on [twitter] or open a github issue.


[flux]: https://github.com/weaveworks/flux
[sealed secrets]: https://github.com/bitnami-labs/sealed-secrets/
[metallb]: https://github.com/google/metallb/
[usg-config]: https://help.ubnt.com/hc/en-us/articles/215458888-UniFi-How-to-further-customize-USG-configuration-with-config-gateway-json
[bootstrap.sh]: bootstrap.sh
[twitter]: https://twitter.com/nicolerenee3810
