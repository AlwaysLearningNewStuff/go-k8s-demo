package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// User represents a database entity.
// In real projects you would place this in domain/models.
type User struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

// Repository provides DB methods.
// In real code you'd separate interface & implementation, but for demo we keep it compact.
type Repository struct {
	db *pgxpool.Pool
}

// NewRepository constructs a new repo.
func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// ---------------------------------------------------------
// DATABASE METHODS
// ---------------------------------------------------------

func (r *Repository) GetAllUsers(ctx context.Context) ([]User, error) {
	rows, err := r.db.Query(ctx, "SELECT id, name, email FROM users ORDER BY id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User

	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email); err != nil {
			return nil, err
		}
		users = append(users, u)
	}

	return users, rows.Err()
}

func (r *Repository) GetUserByID(ctx context.Context, id int64) (*User, error) {
	var u User
	err := r.db.QueryRow(ctx, "SELECT id, name, email FROM users WHERE id=$1", id).
		Scan(&u.ID, &u.Name, &u.Email)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *Repository) CreateUser(ctx context.Context, name, email string) (int64, error) {
	// Demonstrates use of transactions — good practice for write operations.
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var id int64
	err = tx.QueryRow(ctx,
		"INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id",
		name, email,
	).Scan(&id)

	if err != nil {
		return 0, err
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}

	return id, nil
}

func (r *Repository) UpdateUser(ctx context.Context, id int64, name, email string) error {
	cmd, err := r.db.Exec(ctx,
		"UPDATE users SET name=$1, email=$2 WHERE id=$3",
		name, email, id,
	)
	if err != nil {
		return err
	}

	if cmd.RowsAffected() == 0 {
		return errors.New("no rows updated")
	}

	return nil
}

func (r *Repository) DeleteUser(ctx context.Context, id int64) error {
	cmd, err := r.db.Exec(ctx, "DELETE FROM users WHERE id=$1", id)
	if err != nil {
		return err
	}

	if cmd.RowsAffected() == 0 {
		return errors.New("no rows deleted")
	}

	return nil
}

// ---------------------------------------------------------
// HANDLERS
// ---------------------------------------------------------

func registerRoutes(r *gin.Engine, repo *Repository) {

	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "healthy"})
	})

	r.GET("/readyz", func(c *gin.Context) {
		// Simple readiness probe that checks DB connectivity.
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()

		if err := repo.db.Ping(ctx); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"ready": false})
			return
		}

		c.JSON(http.StatusOK, gin.H{"ready": true})
	})

	r.GET("/users", func(c *gin.Context) {
		users, err := repo.GetAllUsers(c.Request.Context())
		if err != nil {
			log.Error().Err(err).Msg("failed to get users")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch users"})
			return
		}
		c.JSON(http.StatusOK, users)
	})

	r.GET("/users/:id", func(c *gin.Context) {
		id, err := parseIDParam(c)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
			return
		}

		u, err := repo.GetUserByID(c.Request.Context(), id)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}

		c.JSON(http.StatusOK, u)
	})

	r.POST("/users", func(c *gin.Context) {
		var payload struct {
			Name  string `json:"name" binding:"required"`
			Email string `json:"email" binding:"required,email"`
		}

		if err := c.ShouldBindJSON(&payload); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload"})
			return
		}

		id, err := repo.CreateUser(c.Request.Context(), payload.Name, payload.Email)
		if err != nil {
			log.Error().Err(err).Msg("failed to create user")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
			return
		}

		c.JSON(http.StatusCreated, gin.H{"id": id})
	})

	r.PUT("/users/:id", func(c *gin.Context) {
		id, err := parseIDParam(c)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
			return
		}

		var payload struct {
			Name  string `json:"name" binding:"required"`
			Email string `json:"email" binding:"required,email"`
		}

		if err := c.ShouldBindJSON(&payload); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload"})
			return
		}

		if err := repo.UpdateUser(c.Request.Context(), id, payload.Name, payload.Email); err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"updated": true})
	})

	r.DELETE("/users/:id", func(c *gin.Context) {
		id, err := parseIDParam(c)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
			return
		}

		if err := repo.DeleteUser(c.Request.Context(), id); err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"deleted": true})
	})
}

func parseIDParam(c *gin.Context) (int64, error) {
	return strconv.ParseInt(c.Param("id"), 10, 64)
}

// ---------------------------------------------------------
// MAIN ENTRYPOINT
// ---------------------------------------------------------

func main() {
	// Zerolog pretty print for local dev, JSON in containers
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal().Msg("DATABASE_URL is required")
	}

	ctx := context.Background()

	// Create pgxpool
	dbpool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create DB pool")
	}

	// Verify DB connectivity
	if err := dbpool.Ping(ctx); err != nil {
		log.Fatal().Err(err).Msg("database not reachable")
	}

	log.Info().Msg("Connected to Postgres")

	repo := NewRepository(dbpool)

	// Gin in release mode by default
	gin.SetMode(gin.ReleaseMode)
	router := gin.New()

	// Logging middleware
	router.Use(gin.Logger())
	router.Use(gin.Recovery())

	registerRoutes(router, repo)

	// Server with graceful shutdown
	srv := &http.Server{
		Addr:    ":8080",
		Handler: router,
	}

	go func() {
		log.Info().Msg("Server starting on :8080")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("server crashed")
		}
	}()

	// Wait for SIGINT/SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit

	log.Info().Msg("Shutting down server...")

	// Graceful shutdown
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error().Err(err).Msg("server forced to shutdown")
	}

	dbpool.Close()
	log.Info().Msg("Server exited cleanly")
}
