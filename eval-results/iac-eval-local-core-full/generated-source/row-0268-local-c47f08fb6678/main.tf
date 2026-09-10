resource "aws_s3_bucket" "website_images" {
  bucket_prefix = "website-images-"

  tags = {
    Name        = "website-images"
    Description = "Stores images for display on a website"
  }
}
