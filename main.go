package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var (
	mealsCreated = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "meals_created_total",
		Help: "Total number of meals created",
	})
	mealsDeleted = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "meals_deleted_total",
		Help: "Total number of meals deleted",
	})
	httpRequests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total number of HTTP requests",
	}, []string{"method", "path", "status"})
)

func init() {
	prometheus.MustRegister(mealsCreated, mealsDeleted, httpRequests)
}

type Meal struct {
	ID       uint    `json:"id" gorm:"primaryKey"`
	Name     string  `json:"name" binding:"required"`
	Calories int     `json:"calories" binding:"required"`
	Protein  float64 `json:"protein"`
	Carbs    float64 `json:"carbs"`
	Fat      float64 `json:"fat"`
}

var db *gorm.DB

func connectDB() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "host=localhost user=postgres password=postgres dbname=caloriedb port=5432 sslmode=disable"
	}
	var err error
	for attempt := 1; attempt <= 10; attempt++ {
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
		if err == nil {
			break
		}
		log.Printf("database not ready (attempt %d/10): %v", attempt, err)
		time.Sleep(3 * time.Second)
	}
	if err != nil {
		panic("failed to connect to database: " + err.Error())
	}
	db.AutoMigrate(&Meal{})
}

func main() {
	connectDB()

	r := gin.Default()

	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	r.GET("/health", func(c *gin.Context) {
		httpRequests.WithLabelValues("GET", "/health", "200").Inc()
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/meals", func(c *gin.Context) {
		var meals []Meal
		db.Find(&meals)
		c.JSON(http.StatusOK, meals)
	})

	r.GET("/meals/:id", func(c *gin.Context) {
		var meal Meal
		if err := db.First(&meal, c.Param("id")).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "meal not found"})
			return
		}
		c.JSON(http.StatusOK, meal)
	})

	r.POST("/meals", func(c *gin.Context) {
		var meal Meal
		if err := c.ShouldBindJSON(&meal); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		db.Create(&meal)
		mealsCreated.Inc()
		httpRequests.WithLabelValues("POST", "/meals", "201").Inc()
		c.JSON(http.StatusCreated, meal)
	})

	r.DELETE("/meals/:id", func(c *gin.Context) {
		var meal Meal
		if err := db.First(&meal, c.Param("id")).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "meal not found"})
			return
		}
		db.Delete(&meal)
		mealsDeleted.Inc()
		httpRequests.WithLabelValues("DELETE", "/meals/:id", "200").Inc()
		c.JSON(http.StatusOK, gin.H{"message": "meal deleted"})
	})

	r.Run(":8080")
}
