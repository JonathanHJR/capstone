resource "aws_ecr_repository" "calorie_tracker" {
  name                 = "calorie-tracker"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "calorie-tracker" }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.calorie_tracker.repository_url
}
