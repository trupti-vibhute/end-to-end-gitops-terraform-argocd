output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS Kubernetes API endpoint"
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "configure_kubectl" {
  description = "Point your local kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "argocd_admin_password_command" {
  description = "Print the initial ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_ui_command" {
  description = "Open the ArgoCD UI at https://localhost:8080 (user: admin)"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "app_url_command" {
  description = "Print the frontend's public load balancer hostname (open it on port 3000)"
  value       = "kubectl get svc frontend -n 3tirewebapp-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
