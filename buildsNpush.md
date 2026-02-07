aws ecr get-login-password --region il-central-1 | docker login --username AWS --password-stdin 923337630273.dkr.ecr.il-central-1.amazonaws.com
Login Succeeded
 
cd /home/shayme/projects/Lab-commit/app/backend && docker build -t 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend:latest -t 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend:v1.0.0 .
cd /home/shayme/projects/Lab-commit/app/frontend && docker build -t 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-frontend:latest -t 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-frontend:v1.0.0 .
docker push 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend:latest && docker push 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend:v1.0.0
docker push 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-frontend:latest && docker push 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-frontend:v1.0.0


helm upgrade backend helm/backend \
  --set image.repository=923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend \
  --set image.tag=v1.0.2 \
  -n lab-commit


aws secretsmanager get-secret-value --secret-id lab-commit-v1-db-password --region il-central-1 --query 'SecretString' --output text
  


  מה גרם ל-ALB להיות healthy?

עשינו rollout restart לדיפלוימנט של ה-frontend וה-backend, מה שגרם לפודים לקבל כתובת IP חדשה ולהירשם מחדש ב-Target Group של ה-ALB.
ה-ALB Controller רשם את הפוד החדש ב-Target Group, עדכן את ה-Security Group, ודירגסטר את הפוד הישן.
ה-Health Check של ה-ALB עבר בהצלחה כי הפוד החדש ענה ב-200 על /health.
פקודות שביצענו:

1. בדיקת שמות הדיפלוימנטס:
kubectl get deployments -n lab-commit

2. Restart לדיפלוימנטס:
kubectl rollout restart deployment backend-backend -n lab-commit
kubectl rollout restart deployment frontend-frontend -n lab-commit

3. בדיקת לוגים של ALB Controller:
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

4. בדיקת ה-Target Group ARN:
kubectl describe ingress frontend-frontend-ingress -n lab-commit

5. שליפת ה-Target Group ARN:
aws elbv2 describe-target-groups --names k8s-labcommi-frontend-73aa4f3f29 --region il-central-1

6. בדיקת סטטוס הבריאות של ה-Target Group:
aws elbv2 describe-target-health --target-group-arn <TargetGroupArn> --region il-central-1


כדי להריץ בדיקות SQL:
נוכל להרים דוקר:
 kubectl run mysql-client --image=mysql:8.0 --rm -it --restart=Never -- bash 
 שימות אחרי השימוש בו (--rm = remove after exit)

mysql -h <DB_HOST> -u <DB_USER> -p<DB_PASSWORD> <DB_NAME>
לדוגמא:
mysql -h lab-commit-v1-db.cnwcoewq02vx.il-central-1.rds.amazonaws.com -u admin -p labcommit

פקודות לעדכון טבלת הגרסאות (version) ב-MySQL
1. בדיקת מבנה הטבלה:
SHOW COLUMNS FROM version;

2. הוספת ערך חדש לגרסה:
INSERT INTO version (value) VALUES ('1.0.4');
(ניתן להחליף את '1.0.4' לכל ערך גרסה שתרצה)

3. צפייה בכל הערכים בטבלה:
SELECT * FROM version;
שים לב: אין צורך לציין את העמודה id כי היא אוטומטית (auto_increment).

אם תרצה דוגמה מלאה להוספה למדריך, הנה דוגמה מסודרת:

או שעושים:
kubectl port-forward svc/backend-service 8080:8080 -n lab-commit
ואז אפשר לפנות לבקאנד בעזרת הפונקציה לעדכון הערך שהוספתי :)

curl -X PUT http://localhost:8080/version/1.0.5
{"status":"updated","version":"1.0.5"}
