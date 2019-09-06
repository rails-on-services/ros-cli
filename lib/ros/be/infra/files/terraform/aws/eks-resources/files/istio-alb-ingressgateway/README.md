# Chart istio-alb-ingressgateway

This chart is in charge of creating a kubernetes ingress resource acting as a istio ingress gateway.

The ingress will be using AWS ALB, so aws-alb-ingress-controller need to be installed first. It has http to https redirect enabled.

The reason why the chart exist is because of the lack of terraform resouce of kubernetes ingress.
